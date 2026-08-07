import CryptoKit
import Foundation

enum ExtensionStoreChannel: String, Codable, CaseIterable, Sendable {
    case verified
    case partial
    case community

    var title: String {
        switch self {
        case .verified: "Verified"
        case .partial: "Partial"
        case .community: "Community"
        }
    }
}

struct ExtensionVerificationReport: Codable, Equatable, Sendable {
    let channel: ExtensionStoreChannel
    let score: Int
    let issues: [String]
    let hardVetoes: [String]
    let bundleBytes: Int
    let bundleHash: String
    let capabilityHash: String
    let manifestName: String?
    let version: String?

    var isInstallable: Bool { hardVetoes.isEmpty && manifestName != nil }
}

struct ExtensionPackageMetadata: Codable, Equatable, Sendable {
    let version: String
    let sourceRepository: String?
    let license: String?
    let lockfileHash: String?
    let architectures: [String]?
    let commit: String?
    let verifiedAt: Date?
    let verified: Bool?
}

enum ExtensionPackageValidationError: LocalizedError {
    case notDirectory
    case unsafePath
    case missingFile(String)
    case invalidManifest
    case invalidCapabilities
    case invalidBuild
    case bundleTooLarge
    case hashMismatch
    case capabilityMismatch
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notDirectory: "Extension package must be a folder."
        case .unsafePath: "Extension package contains an unsafe path."
        case .missingFile(let name): "Extension package is missing \(name)."
        case .invalidManifest: "Extension manifest is invalid."
        case .invalidCapabilities: "Extension capability metadata is invalid."
        case .invalidBuild: "Extension build metadata is invalid."
        case .bundleTooLarge: "Extension bundle exceeds the 8 MB admission limit."
        case .hashMismatch: "Extension bundle hash does not match build metadata."
        case .capabilityMismatch: "Manifest capabilities do not match the capability bridge usage."
        case .rejected(let reason): reason
        }
    }
}

struct ExtensionPackageValidator {
    static let maximumBundleBytes = 8 * 1024 * 1024

    private struct CapabilityFile: Decodable {
        let schemaVersion: Int
        let capabilities: [Capability]
    }

    private struct Capability: Decodable {
        let name: String
    }

    private struct BuildFile: Decodable {
        let schemaVersion: Int
        let bundleHash: String
        let capabilityHash: String
        let bundleBytes: Int
        let capabilitiesUsed: [String]?
    }

    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func validate(packageURL: URL, trustedVerification: Bool = false) throws -> ExtensionVerificationReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw ExtensionPackageValidationError.notDirectory }
        guard packageURL.pathExtension == "ocx", !packageURL.lastPathComponent.contains("..") else {
            throw ExtensionPackageValidationError.unsafePath
        }
        let packageFiles = try FileManager.default.subpathsOfDirectory(atPath: packageURL.path)
        for relativePath in packageFiles {
            let fileURL = packageURL.appendingPathComponent(relativePath)
            if try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ExtensionPackageValidationError.unsafePath
            }
        }

        let manifest = try decode(
            ExtensionManifest.self, at: packageURL.appendingPathComponent("manifest.json"), error: .invalidManifest)
        guard manifest.schemaVersion == 1, validIdentifier(manifest.name), !manifest.commands.isEmpty,
            manifest.commands.allSatisfy({
                validIdentifier($0.name) && validEntry($0.entry)
                    && ($0.mode == "view" || $0.mode == "no-view" || $0.mode == "menu-bar")
                    && ($0.mode != "menu-bar" || $0.menuBar == true)
                    && ($0.preferences ?? []).allSatisfy(validPreference)
            })
        else { throw ExtensionPackageValidationError.invalidManifest }
        guard (manifest.preferences ?? []).allSatisfy(validPreference) else {
            throw ExtensionPackageValidationError.invalidManifest
        }
        guard
            manifest.commands.allSatisfy({ command in
                !((command.capabilities ?? []).contains("network.request"))
                    || !(command.networkDomains ?? []).isEmpty
            })
        else { throw ExtensionPackageValidationError.invalidManifest }
        guard manifest.commands.allSatisfy(validScopes) else {
            throw ExtensionPackageValidationError.invalidManifest
        }
        let capabilitiesURL = packageURL.appendingPathComponent("capabilities.json")
        let capabilitiesData = try Data(contentsOf: capabilitiesURL)
        let capabilities = try decode(
            CapabilityFile.self, at: capabilitiesURL, error: .invalidCapabilities
        )
        guard capabilities.schemaVersion == 1 else { throw ExtensionPackageValidationError.invalidCapabilities }
        let build = try decode(
            BuildFile.self, at: packageURL.appendingPathComponent("build.json"), error: .invalidBuild)
        guard build.schemaVersion == 1 else { throw ExtensionPackageValidationError.invalidBuild }
        let bundleURL = packageURL.appendingPathComponent("bundle.js")
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ExtensionPackageValidationError.missingFile("bundle.js")
        }

        let bundleData = try Data(contentsOf: bundleURL)
        guard bundleData.count <= Self.maximumBundleBytes else { throw ExtensionPackageValidationError.bundleTooLarge }
        let hash = SHA256.hash(data: bundleData).map { String(format: "%02x", $0) }.joined()
        guard hash == build.bundleHash, bundleData.count == build.bundleBytes else {
            throw ExtensionPackageValidationError.hashMismatch
        }
        let manifestData = try Data(contentsOf: packageURL.appendingPathComponent("manifest.json"))
        var capabilityContract = manifestData
        capabilityContract.append(capabilitiesData)
        let capabilityHash = SHA256.hash(data: capabilityContract).map { String(format: "%02x", $0) }.joined()
        guard capabilityHash == build.capabilityHash else {
            throw ExtensionPackageValidationError.capabilityMismatch
        }

        let manifestCapabilities = Set(manifest.commands.flatMap { $0.capabilities ?? [] })
        let fileCapabilities = Set(capabilities.capabilities.map(\.name))
        let usedCapabilities: Set<String>
        if let declaredUsage = build.capabilitiesUsed {
            usedCapabilities = Set(declaredUsage)
        } else {
            usedCapabilities = usedCapabilityNames(in: String(decoding: bundleData, as: UTF8.self))
        }
        guard manifestCapabilities == fileCapabilities, usedCapabilities.isSubset(of: manifestCapabilities) else {
            throw ExtensionPackageValidationError.capabilityMismatch
        }

        let metadata = try? decode(
            ExtensionPackageMetadata.self, at: packageURL.appendingPathComponent("verification.json"),
            error: .invalidBuild)
        let hardVetoes = hardVetoes(in: packageURL, bundle: String(decoding: bundleData, as: UTF8.self))
        let issues = issues(
            manifest: manifest, metadata: metadata, usedCapabilities: usedCapabilities, hardVetoes: hardVetoes)
        let score = score(metadata: metadata, issues: issues, hardVetoes: hardVetoes)
        let channel: ExtensionStoreChannel =
            trustedVerification && metadata?.verified == true && hardVetoes.isEmpty && issues.isEmpty
            ? .verified : metadata != nil ? .partial : .community
        return ExtensionVerificationReport(
            channel: channel,
            score: score,
            issues: issues,
            hardVetoes: hardVetoes,
            bundleBytes: bundleData.count,
            bundleHash: hash,
            capabilityHash: capabilityHash,
            manifestName: manifest.name,
            version: metadata?.version
        )
    }

    private func validIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        return !parts.isEmpty
            && parts.allSatisfy { part in
                !part.isEmpty
                    && part.allSatisfy {
                        $0.isASCII && ($0.isNumber || ($0.isLetter && $0.isLowercase))
                    }
            }
    }

    private func validEntry(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && !value.contains("..")
    }

    private func validPreference(_ preference: ExtensionManifestPreference) -> Bool {
        let validName =
            preference.name.count <= 80
            && preference.name.first?.isLetter == true
            && preference.name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        let normalizedName = preference.name.lowercased().replacingOccurrences(of: "_", with: "")
        let forbiddenCredentialName = ["apikey", "token", "oauth", "clientsecret"].contains {
            normalizedName.contains($0)
        }
        let validType = ["textfield", "password", "checkbox", "dropdown", "date"].contains(preference.type)
        let validOptions = preference.type != "dropdown" || !preference.options.isEmpty
        return validName && !forbiddenCredentialName && validType && validOptions
    }

    private func validScopes(_ command: ExtensionManifestCommand) -> Bool {
        let executables = command.executables ?? []
        let roots = command.filesystemRoots ?? []
        let domains = command.networkDomains ?? []
        return domains.allSatisfy(validDomainScope)
            && executables.allSatisfy {
                let path = URL(fileURLWithPath: $0).standardizedFileURL.path
                return $0 == path
                    && ["/bin", "/usr/bin", "/usr/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
                        .contains(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            } && roots.allSatisfy { $0 == "extension" || $0 == "home" || $0.hasPrefix("home/") }
    }

    private func validDomainScope(_ value: String) -> Bool {
        let scope = value.lowercased()
        let host = scope.hasPrefix("*.") ? String(scope.dropFirst(2)) : scope
        guard !host.isEmpty, !host.contains("/"), !host.contains(":"), !host.contains("*") else { return false }
        return host.split(separator: ".").allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL, error: ExtensionPackageValidationError) throws -> T {
        guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(type, from: data) else {
            if case .missingFile = error { throw error }
            throw error
        }
        return value
    }

    private func usedCapabilityNames(in bundle: String) -> Set<String> {
        let pattern = #"requestCapability\([\"']([^\"']+)[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return Set(
            expression.matches(in: bundle, range: NSRange(bundle.startIndex..., in: bundle)).compactMap {
                guard let range = Range($0.range(at: 1), in: bundle) else { return nil }
                return String(bundle[range])
            })
    }

    private func hardVetoes(in packageURL: URL, bundle: String) -> [String] {
        var vetoes: [String] = []
        let packageFiles = (try? FileManager.default.subpathsOfDirectory(atPath: packageURL.path)) ?? []
        if packageFiles.contains(where: { $0.hasSuffix(".node") || $0.hasSuffix(".dylib") || $0.hasSuffix(".so") }) {
            vetoes.append("native addon or opaque binary")
        }
        if packageFiles.contains(where: { $0 == "postinstall" || $0.hasSuffix("/postinstall") }) {
            vetoes.append("postinstall script")
        }
        let forbiddenPatterns = [
            "child_process", "process.mainModule", "eval(", "new Function(",
            "XMLHttpRequest", "import(\"http", "import(\"https",
        ]
        for pattern in forbiddenPatterns where bundle.contains(pattern) {
            vetoes.append(pattern)
        }
        if bundle.range(of: #"from\s+["']@raycast/(?:api|utils)["']"#, options: .regularExpression) != nil,
            bundle.contains("AI")
        {
            vetoes.append("AI API")
        }
        return Array(Set(vetoes)).sorted()
    }

    private func issues(
        manifest: ExtensionManifest,
        metadata: ExtensionPackageMetadata?,
        usedCapabilities: Set<String>,
        hardVetoes: [String]
    ) -> [String] {
        var issues = hardVetoes
        if manifest.license == nil && metadata?.license == nil { issues.append("license is not declared") }
        if metadata?.sourceRepository == nil { issues.append("source repository is not declared") }
        if metadata?.lockfileHash == nil { issues.append("dependency lockfile is not pinned") }
        if metadata?.commit == nil { issues.append("source commit is not recorded") }
        if metadata?.architectures?.sorted() != ["arm64", "x86_64"] {
            issues.append("both supported architectures are not verified")
        }
        return Array(Set(issues)).sorted()
    }

    private func score(metadata: ExtensionPackageMetadata?, issues: [String], hardVetoes: [String]) -> Int {
        guard hardVetoes.isEmpty else { return 0 }
        var score = 55
        if metadata?.sourceRepository != nil { score += 10 }
        if metadata?.lockfileHash != nil { score += 10 }
        if metadata?.commit != nil { score += 10 }
        if metadata?.architectures?.sorted() == ["arm64", "x86_64"] { score += 10 }
        if metadata?.license != nil { score += 5 }
        return max(0, score - max(0, issues.count - 1) * 5)
    }
}
