import CoreGraphics
import Foundation

public protocol WindowSystem {
    @discardableResult
    func refresh() -> [WindowSnapshot]
    func contains(_ id: WindowID) -> Bool
    func focusedWindowID() -> WindowID?
    func snapshot(for id: WindowID) -> WindowSnapshot?
    func frame(for id: WindowID) -> WindowFrame?
    func setPosition(_ point: CGPoint, for id: WindowID) throws
    func setFrame(_ frame: WindowFrame, for id: WindowID) throws
    func focus(_ id: WindowID)
}
