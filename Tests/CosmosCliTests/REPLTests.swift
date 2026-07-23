import CoreGraphics
@testable import CosmosCli
import CosmosCore
import XCTest

final class REPLTests: XCTestCase {
    func testMissingSpaceCommandsAreNoOpsWithHonestOutput() throws {
        let windowSystem = CLIWindowSystem(windows: [Self.window(id: 100)])
        let (repl, output) = makeREPL(windowSystem: windowSystem)
        _ = try repl.execute(.list)

        XCTAssertTrue(try repl.execute(.switchSpace("A")))
        XCTAssertTrue(try repl.execute(.moveWindow("A")))

        XCTAssertEqual(Array(output.lines.suffix(2)), [
            "space not found; no changes",
            "space not found; no changes"
        ])
    }

    func testListSynchronizesAndPrintsNewManagedWindows() throws {
        let windowSystem = CLIWindowSystem(windows: [Self.window(id: 100)])
        let (repl, output) = makeREPL(windowSystem: windowSystem)

        XCTAssertTrue(try repl.execute(.list))

        XCTAssertTrue(output.lines.contains("auto-assigned 100 -> 1"))
        XCTAssertTrue(output.lines.contains { $0.contains("100 ws=1 visible") })
    }

    func testQuitStopsCommandLoop() throws {
        let (repl, output) = makeREPL(windowSystem: CLIWindowSystem())

        XCTAssertFalse(try repl.execute(.quit))
        XCTAssertTrue(output.lines.isEmpty)
    }

    private func makeREPL(
        windowSystem: CLIWindowSystem
    ) -> (REPL, CLIOutputBuffer) {
        let output = CLIOutputBuffer()
        let controller = SpaceController(
            windowSystem: windowSystem,
            displayProvider: CLIDisplayProvider()
        )
        let repl = REPL(
            controller: controller,
            ensureAccessibilityPermission: { _ in true },
            output: { output.lines.append($0) }
        )
        return (repl, output)
    }

    private static func window(id: WindowID) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            app: RunningAppInfo(pid: 1, name: "Fixture"),
            title: "Window \(id)",
            frame: WindowFrame(origin: .zero, size: CGSize(width: 800, height: 600)),
            isMinimized: false
        )
    }
}

private final class CLIOutputBuffer {
    var lines: [String] = []
}

private final class CLIWindowSystem: WindowSystem {
    var windows: [WindowSnapshot]
    var focusedWindowIDValue: WindowID?

    init(windows: [WindowSnapshot] = []) {
        self.windows = windows
    }

    func refresh() throws -> [WindowSnapshot] {
        windows
    }

    func contains(_ id: WindowID) -> Bool {
        windows.contains { $0.id == id }
    }

    func focusedWindowID() -> WindowID? {
        focusedWindowIDValue
    }

    func frame(for id: WindowID) -> WindowFrame? {
        windows.first { $0.id == id }?.frame
    }

    func setPosition(_: CGPoint, for _: WindowID) throws {}
    func setFrame(_: WindowFrame, for _: WindowID) throws {}
    func focus(_ id: WindowID) {
        focusedWindowIDValue = id
    }
}

private struct CLIDisplayProvider: DisplayProviding {
    func displays() throws -> [DisplaySnapshot] {
        [DisplaySnapshot(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            role: .main
        )]
    }
}
