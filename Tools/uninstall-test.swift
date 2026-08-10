import Foundation

@main
struct UninstallTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "opencast-uninstall-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = Data(repeating: 0x41, count: 593)
        let second = Data(repeating: 0x42, count: 1_237)
        let firstURL = root.appendingPathComponent("first.txt")
        let secondURL = root.appendingPathComponent("second.txt")
        try first.write(to: firstURL)
        try second.write(to: secondURL)

        precondition(AppLeftovers.size(of: firstURL) == Int64(first.count))
        precondition(AppLeftovers.size(of: root) == Int64(first.count + second.count))

        let link = root.deletingLastPathComponent().appendingPathComponent("opencast-uninstall-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstURL)
        defer { try? FileManager.default.removeItem(at: link) }
        precondition(AppLeftovers.size(of: link) == nil)

        print("uninstall tests passed")
    }
}
