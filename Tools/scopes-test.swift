import Foundation

@main
struct ScopesTest {
    static func main() {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("opencast-scopes-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS \(description)")
            } else {
                print("FAIL \(description)")
                failures += 1
            }
        }

        func makeDirectory(_ url: URL) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let apps = root.appendingPathComponent("Apps")
        makeDirectory(apps.appendingPathComponent("Alpha.app"))
        makeDirectory(apps.appendingPathComponent("Beta.app"))
        let host = apps.appendingPathComponent("Host.app")
        makeDirectory(host.appendingPathComponent("Contents/Applications/Child.app"))
        makeDirectory(host.appendingPathComponent("Contents/Resources/Noise.app"))
        makeDirectory(apps.appendingPathComponent("Notes.txt"))
        makeDirectory(apps.appendingPathComponent(".Hidden.app"))
        let nested = apps.appendingPathComponent("Sub")
        makeDirectory(nested.appendingPathComponent("Deep.app"))
        makeDirectory(nested.appendingPathComponent("Vendor/TooDeep.app"))

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check(
            "direct .app children are indexed",
            Set(found).isSuperset(of: ["Alpha.app", "Beta.app", "Host.app"]))
        check("embedded apps in Contents/Applications are indexed", found.contains("Child.app"))
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("unrelated app contents are skipped", !found.contains("Noise.app"))
        check("apps in one grouped folder are indexed", found.contains("Deep.app"))
        check("deeper grouped folders are skipped", !found.contains("TooDeep.app"))
        check(
            "a nested folder works as its own scope",
            SearchScopes.appBundles(in: [nested.path]).map(\.lastPathComponent) == ["Deep.app"])
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, nested.path])
                .map(\.lastPathComponent) == ["Deep.app"])
        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [nested.path, apps.path]).map(\.lastPathComponent).first
                == "Deep.app")

        let home = fileManager.homeDirectoryForCurrentUser.path
        check("expand resolves a tilde", SearchScopes.expand("~/Applications") == home + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications") == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/") == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/") == "/")
        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications",
            ]) == ["/Applications", "~/Applications"])
        check(
            "normalize preserves order",
            SearchScopes.normalize(["/B", "/A"]) == ["/B", "/A"])
        check("normalize drops blanks", SearchScopes.normalize([" ", "/A"]) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
