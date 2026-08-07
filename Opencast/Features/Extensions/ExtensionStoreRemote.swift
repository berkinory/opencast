import Foundation

struct ExtensionStoreCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let packages: [ExtensionStorePackage]
}

struct ExtensionStorePackage: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let title: String
    let description: String
    let version: String
    let packageURL: URL
    let bundleHash: String
    let capabilityHash: String
    let bundleBytes: Int
    let minimumAppVersion: String
    let capabilities: [String]
    let sourceRepository: URL?
    let license: String?
    let verified: Bool

    var id: String { name }
}

enum ExtensionStoreError: LocalizedError {
    case invalidCatalog
    case invalidPackageURL
    case packageTooLarge
    case packageMismatch
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The Extension Store catalog is invalid."
        case .invalidPackageURL: "The extension package URL is not trusted."
        case .packageTooLarge: "The extension package is too large."
        case .packageMismatch: "The downloaded package does not match the catalog."
        case let .archiveFailed(message): "Could not unpack the extension package: " + message
        }
    }
}
