import CoreGraphics
@testable import KkaciCore

extension WindowFrame {
    static func frame(x: CGFloat, y: CGFloat, width: CGFloat = 100, height: CGFloat = 100) -> WindowFrame {
        WindowFrame(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}

extension WindowSnapshot {
    static func window(id: WindowID, title: String, isMinimized: Bool = false) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            app: RunningAppInfo(pid: 1, name: "FakeApp", bundleID: "test.fake"),
            title: title,
            frame: .frame(x: CGFloat(id), y: CGFloat(id)),
            isMinimized: isMinimized
        )
    }
}
