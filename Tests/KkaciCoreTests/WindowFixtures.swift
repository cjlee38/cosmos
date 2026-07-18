import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

extension WindowFrame {
    static func frame(x: CGFloat, y: CGFloat, width: CGFloat = 100, height: CGFloat = 100) -> WindowFrame {
        WindowFrame(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}

extension WindowSnapshot {
    static func window(
        id: WindowID,
        title: String,
        pid: pid_t = 1,
        appName: String = "FakeApp",
        frame: WindowFrame? = nil,
        isMinimized: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            app: RunningAppInfo(pid: pid, name: appName),
            title: title,
            frame: frame ?? .frame(x: CGFloat(id), y: CGFloat(id)),
            isMinimized: isMinimized
        )
    }
}

func workspaceConfigs(
    _ ids: [String],
    displays: [String: MonitorSlot] = [:]
) -> [WorkspaceConfig] {
    ids.map { value in
        guard let id = WorkspaceID(rawValue: value) else {
            preconditionFailure("Invalid workspace ID in test: \(value)")
        }
        return WorkspaceConfig(id: id, display: displays[value] ?? 1)
    }
}

func configuredMonitorSlot(
    for workspace: String,
    in controller: WorkspaceController
) -> MonitorSlot? {
    controller.currentConfig.workspaces.first { $0.id.rawValue == workspace }?.display
}

func assertReassigned(
    _ actual: [HiddenWindowRecordAssignment],
    _ expected: [(WindowID, WorkspaceID)],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.map(\.windowID), expected.map(\.0), file: file, line: line)
    XCTAssertEqual(actual.map(\.workspace), expected.map(\.1), file: file, line: line)
}
