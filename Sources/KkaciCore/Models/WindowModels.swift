import CoreGraphics
import Foundation

public typealias WindowID = CGWindowID

public struct RunningAppInfo: Equatable {
    public let pid: pid_t
    public let name: String
    public let bundleID: String?

    public init(pid: pid_t, name: String, bundleID: String?) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
    }
}

public struct WindowFrame: Codable, Equatable {
    public var origin: CGPoint
    public var size: CGSize

    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    public var center: CGPoint {
        CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }
}

public struct WindowSnapshot {
    public let id: WindowID
    public let app: RunningAppInfo
    public let title: String
    public let frame: WindowFrame?
    public let isMinimized: Bool

    public init(id: WindowID, app: RunningAppInfo, title: String, frame: WindowFrame?, isMinimized: Bool) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }
}
