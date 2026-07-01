import CoreGraphics
import Foundation
@testable import KkaciCore

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
        bundleID: String? = "test.fake",
        frame: WindowFrame? = nil,
        isMinimized: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            app: RunningAppInfo(pid: pid, name: appName, bundleID: bundleID),
            title: title,
            frame: frame ?? .frame(x: CGFloat(id), y: CGFloat(id)),
            isMinimized: isMinimized
        )
    }
}
