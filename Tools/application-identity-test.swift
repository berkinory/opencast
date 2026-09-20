import Foundation

@main
struct ApplicationIdentityTests {
    static func main() {
        var paths: [String: String] = [:]
        let stable = URL(fileURLWithPath: "/Applications/Xcode.app")
        let beta = URL(fileURLWithPath: "/Applications/Xcode-beta.app")
        let bundle = "com.apple.dt.Xcode"
        precondition(ApplicationIdentity.key(for: stable, bundleID: bundle, primaryPaths: &paths) == bundle)
        let betaKey = ApplicationIdentity.key(for: beta, bundleID: bundle, primaryPaths: &paths)
        precondition(betaKey == ApplicationIdentity.path(beta))
        precondition(ApplicationIdentity.key(for: beta, bundleID: bundle, primaryPaths: &paths) == betaKey)
        precondition(ApplicationIdentity.key(for: stable, bundleID: bundle, primaryPaths: &paths) == bundle)
        var restored = paths
        precondition(ApplicationIdentity.key(for: beta, bundleID: bundle, primaryPaths: &restored) == betaKey)
        precondition(ApplicationIdentity.key(for: beta, bundleID: nil, primaryPaths: &restored) == betaKey)
        print("application identity tests passed")
    }
}
