import CoreGraphics
import Foundation

public protocol HidePointProviding {
    func hidePoint(for frame: WindowFrame) -> CGPoint
}

public struct DisplaySnapshot: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isMain: Bool

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect? = nil, isMain: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.isMain = isMain
    }
}

public protocol DisplayProviding: HidePointProviding {
    func displays() -> [DisplaySnapshot]
}

public protocol WindowSystem {
    @discardableResult
    func refresh() -> [WindowSnapshot]
    func contains(_ id: WindowID) -> Bool
    func focusedWindowID() -> WindowID?
    func frame(for id: WindowID) -> WindowFrame?
    func setPosition(_ point: CGPoint, for id: WindowID) throws
    func setFrame(_ frame: WindowFrame, for id: WindowID) throws
    func focus(_ id: WindowID)
}

extension WindowSystem {
    func setFrameIfSizeChanged(_ targetFrame: WindowFrame, for id: WindowID) throws {
        if let currentFrame = frame(for: id), currentFrame.size == targetFrame.size {
            try setPosition(targetFrame.origin, for: id)
        } else {
            try setFrame(targetFrame, for: id)
        }
    }
}
