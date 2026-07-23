import CoreGraphics
import Foundation
@testable import CosmosCore
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

func spaceConfigs(
    _ ids: [String],
    displays: [String: MonitorSlot] = [:]
) -> [SpaceConfig] {
    ids.map { value in
        guard let id = SpaceID(rawValue: value) else {
            preconditionFailure("Invalid space ID in test: \(value)")
        }
        return SpaceConfig(id: id, display: displays[value] ?? 1)
    }
}

func configuredMonitorSlot(
    for space: String,
    in controller: SpaceController
) -> MonitorSlot? {
    controller.currentConfig.spaces.first { $0.id.rawValue == space }?.display
}

func assertReassigned(
    _ actual: [HiddenWindowRecordAssignment],
    _ expected: [(WindowID, SpaceID)],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.map(\.windowID), expected.map(\.0), file: file, line: line)
    XCTAssertEqual(actual.map(\.space), expected.map(\.1), file: file, line: line)
}
