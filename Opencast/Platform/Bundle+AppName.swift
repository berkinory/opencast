import Foundation

extension Bundle {
    /// The app's display name, driven by CFBundleDisplayName/CFBundleName in the generated Info.plist.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Opencast"
    }
}
