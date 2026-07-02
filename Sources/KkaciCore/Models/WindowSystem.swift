import CoreGraphics
import Foundation

public protocol HidePointProviding {
    func hidePoint(for frame: WindowFrame) -> CGPoint
}

public protocol WindowSystem {
    @discardableResult
    func refresh() -> [WindowSnapshot]
    func contains(_ id: WindowID) -> Bool
    func focusedWindowID() -> WindowID?
    func snapshot(for id: WindowID) -> WindowSnapshot?
    func frame(for id: WindowID) -> WindowFrame?
    func setPosition(_ point: CGPoint, for id: WindowID) throws
    func focus(_ id: WindowID)
}
