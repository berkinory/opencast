// Standalone contract tests for the pure window-management geometry and action memory.
// Run: swiftc -swift-version 6 Opencast/Features/WindowManagement/WindowCommand.swift \
//     Opencast/Features/WindowManagement/WindowLayout.swift \
//     Opencast/Features/WindowManagement/WindowActionMemory.swift Tools/window-command-test.swift \
//     -o /tmp/window-command-test && /tmp/window-command-test

import CoreGraphics
import Foundation

@main
@MainActor
struct WindowCommandTests {
    static var failures = 0
    static var passes = 0

    static let mainScreen = WindowLayout.Screen(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
    )

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectRect(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        expect(actual == expected, "\(message) — got \(actual), expected \(expected)")
    }

    static func frame(
        _ command: WindowCommand.ID,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400),
        screen: WindowLayout.Screen = mainScreen,
        gap: CGFloat = 0,
        restore: CGRect? = nil,
        lastTile: WindowCommand.ID? = nil,
        screens: [WindowLayout.Screen]? = nil
    ) -> CGRect? {
        WindowLayout.placement(
            for: WindowLayout.Input(
                command: command,
                windowFrame: window,
                screens: screens ?? [screen],
                gap: gap,
                restoreFrame: restore,
                lastTileCommand: lastTile
            )
        )?.frame
    }

    static func main() {
        testCatalog()
        testGeometry()
        testGapsAndBoundaries()
        testDisplays()
        testRestore()
        testMemory()
        testFuzz()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testCatalog() {
        let commands = WindowCommandCatalog.all
        expect(commands.count == 26, "catalog contains the focused command set")
        expect(Set(commands.map(\.id)).count == commands.count, "command IDs are unique")
        expect(Set(commands.map(\.entryID)).count == commands.count, "entry IDs are unique")
        expect(Set(commands.map { $0.name.lowercased() }).count == commands.count, "names are unique")
        expect(commands.allSatisfy { !$0.name.isEmpty && !$0.sfSymbol.isEmpty }, "metadata is complete")
        for command in commands {
            expect(
                WindowCommandCatalog.command(forEntryID: command.entryID) == command,
                "entry ID round-trips for \(command.id.rawValue)"
            )
        }
        expect(
            WindowCommandCatalog.command(forEntryID: "system-command:sleep") == nil,
            "system commands keep their namespace"
        )
        expect(
            Set(commands.filter { !$0.resizes }.map(\.id))
                == [.moveLeft, .moveRight, .moveUp, .moveDown],
            "only nudges leave the size unchanged"
        )
        expect(
            Set(commands.filter { $0.kind == .fullscreen }.map(\.id)) == [.toggleFullscreen],
            "only fullscreen uses the native fullscreen path"
        )
        expect(
            Set(commands.filter { $0.kind == .restore }.map(\.id)) == [.restore],
            "only restore uses memory"
        )
        let grouped = WindowCommandCatalog.grouped()
        expect(grouped.flatMap(\.commands).count == commands.count, "grouping loses no command")
        expect(grouped.first { $0.group == .sizing }?.commands.count == 6, "six sizing commands")
        expect(frame(.toggleFullscreen) == nil, "fullscreen has no synthetic geometry")
    }

    static func testGeometry() {
        let visible = mainScreen.visibleFrame
        expectRect(frame(.leftHalf)!, CGRect(x: 0, y: 0, width: 720, height: 900), "left half")
        expectRect(frame(.rightHalf)!, CGRect(x: 720, y: 0, width: 720, height: 900), "right half")
        expectRect(frame(.topHalf)!, CGRect(x: 0, y: 0, width: 1440, height: 450), "top half")
        expectRect(frame(.bottomHalf)!, CGRect(x: 0, y: 450, width: 1440, height: 450), "bottom half")
        expectRect(frame(.topLeftQuarter)!, CGRect(x: 0, y: 0, width: 720, height: 450), "top-left quarter")
        expectRect(frame(.bottomRightQuarter)!, CGRect(x: 720, y: 450, width: 720, height: 450), "bottom-right quarter")
        expectRect(frame(.firstThird)!, CGRect(x: 0, y: 0, width: 480, height: 900), "first third")
        expectRect(frame(.centerThird)!, CGRect(x: 480, y: 0, width: 480, height: 900), "center third")
        expectRect(frame(.lastTwoThirds)!, CGRect(x: 480, y: 0, width: 960, height: 900), "last two thirds")
        expectRect(frame(.maximize)!, visible, "maximize fills visible frame")
        expectRect(frame(.maximizeHeight)!, CGRect(x: 100, y: 0, width: 600, height: 900), "maximize height")
        expectRect(frame(.maximizeWidth)!, CGRect(x: 0, y: 100, width: 1440, height: 400), "maximize width")
        expectRect(frame(.center)!, CGRect(x: 420, y: 250, width: 600, height: 400), "center")
        expectRect(frame(.centerHalf)!, CGRect(x: 360, y: 0, width: 720, height: 900), "center half")
        expect(frame(.moveLeft)!.origin.x < 100, "move left")
        expect(frame(.moveRight)!.origin.x > 100, "move right")
        expect(frame(.moveUp)!.origin.y < 100, "move up")
        expect(frame(.moveDown)!.origin.y > 100, "move down")
    }

    static func testGapsAndBoundaries() {
        let gap: CGFloat = 16
        expectRect(
            frame(.leftHalf, gap: gap)!,
            CGRect(x: 16, y: 16, width: 696, height: 868),
            "left half applies outer and inner gaps"
        )
        expectRect(
            frame(.rightHalf, gap: gap)!,
            CGRect(x: 728, y: 16, width: 696, height: 868),
            "right half applies outer and inner gaps"
        )
        let left = frame(.leftHalf, gap: gap)!
        let right = frame(.rightHalf, gap: gap)!
        expect(left.maxX + gap == right.minX, "adjacent tiles preserve the gap")
        expect(
            frame(
                .maximizeHeight,
                window: CGRect(x: -800, y: 200, width: 600, height: 400),
                gap: gap
            )!.isContained(in: WindowLayout.canvas(mainScreen.visibleFrame, gap: gap)),
            "maximize height clamps an off-screen window"
        )
        expect(
            frame(
                .maximizeWidth,
                window: CGRect(x: 200, y: 1200, width: 600, height: 400),
                gap: gap
            )!.isContained(in: WindowLayout.canvas(mainScreen.visibleFrame, gap: gap)),
            "maximize width clamps an off-screen window"
        )
        expect(
            frame(.leftHalf, gap: 10_000)!.width > 0,
            "absurd gaps never create an invalid frame"
        )
    }

    static func testDisplays() {
        let second = WindowLayout.Screen(
            id: 2,
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )
        let moved = frame(
            .nextDisplay,
            window: CGRect(x: 100, y: 100, width: 600, height: 400),
            screens: [mainScreen, second]
        )!
        expect(moved.minX >= second.visibleFrame.minX, "next display moves right")
        expect(
            frame(
                .nextDisplay,
                window: CGRect(x: 100, y: 100, width: 600, height: 400),
                lastTile: .firstThird,
                screens: [mainScreen, second]
            )!.width == second.visibleFrame.width / 3,
            "display move preserves a tile family"
        )
        expect(
            frame(.nextDisplay, screens: [mainScreen]) == nil,
            "display move is a no-op with one display"
        )
    }

    static func testRestore() {
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)
        expect(
            frame(.restore, window: original, restore: nil) == nil,
            "restore without memory is a no-op"
        )
        let restored = frame(.restore, window: .zero, restore: original)!
        expectRect(restored, original, "restore returns the saved frame")
        let stranded = CGRect(x: 5000, y: 5000, width: 400, height: 300)
        let recovered = frame(.restore, window: .zero, restore: stranded)!
        expect(
            mainScreen.visibleFrame.contains(recovered.center),
            "off-screen restore is brought back onto the display"
        )
    }

    static func testMemory() {
        var memory = WindowActionMemory<Int>(capacity: 2)
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)
        let first = memory.decide(key: 1, currentFrame: original)
        expect(!first.canRestore, "first observation has no restore target")
        let left = frame(.leftHalf)!
        memory.commit(key: 1, command: .leftHalf, decision: first, appliedFrame: left)
        let same = memory.decide(key: 1, currentFrame: left)
        expect(same.canRestore, "a moved window becomes restorable")
        expectRect(same.restoreFrame, original, "restore target survives another command")
        expect(same.lastTileCommand == .leftHalf, "last tile is remembered")
        let userMoved = CGRect(x: 300, y: 200, width: 500, height: 350)
        let afterDrag = memory.decide(key: 1, currentFrame: userMoved)
        expectRect(afterDrag.restoreFrame, userMoved, "a user move re-anchors restore")
        expect(afterDrag.lastTileCommand == nil, "a user move forgets the tile")
        memory.commit(key: 1, command: .center, decision: afterDrag, appliedFrame: frame(.center)!)
        memory.commit(
            key: 2,
            command: .maximize,
            decision: memory.decide(key: 2, currentFrame: original),
            appliedFrame: frame(.maximize)!
        )
        memory.commit(
            key: 3,
            command: .center,
            decision: memory.decide(key: 3, currentFrame: original),
            appliedFrame: frame(.center)!
        )
        expect(memory.count == 2, "memory remains bounded")
        expect(memory.record(for: 1) == nil, "least recently used window is evicted")
    }

    static func testFuzz() {
        let commands = WindowCommandCatalog.all.filter { $0.kind != .fullscreen }
        for index in 0..<500 {
            let window = CGRect(
                x: CGFloat((index * 137) % 2400) - 800,
                y: CGFloat((index * 71) % 1600) - 500,
                width: CGFloat(120 + (index * 31) % 1200),
                height: CGFloat(100 + (index * 47) % 800)
            )
            for command in commands {
                guard let placement = frame(command.id, window: window, gap: CGFloat(index % 24))
                else { continue }
                expect(
                    placement.width > 0 && placement.height > 0,
                    "fuzz placement remains positive for \(command.id.rawValue)"
                )
            }
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func isContained(in other: CGRect) -> Bool {
        minX >= other.minX && minY >= other.minY
            && maxX <= other.maxX && maxY <= other.maxY
    }
}
