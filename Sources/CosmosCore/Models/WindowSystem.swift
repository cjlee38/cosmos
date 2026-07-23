import CoreGraphics
import Foundation

public typealias DisplayID = CGDirectDisplayID

public protocol HidePointProviding {
    func hidePoint(for frame: WindowFrame) throws -> CGPoint
}

public enum DisplayRole: Equatable {
    case main
    case extended
}

public struct DisplaySnapshot: Equatable {
    public let id: DisplayID
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let role: DisplayRole

    public init(
        id: DisplayID,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect? = nil,
        role: DisplayRole
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.role = role
    }

    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect? = nil, role: DisplayRole) {
        self.init(
            id: id,
            name: "Display \(id)",
            frame: frame,
            visibleFrame: visibleFrame,
            role: role
        )
    }

    public var isMain: Bool {
        role == .main
    }
}

public protocol DisplayProviding {
    func displays() throws -> [DisplaySnapshot]
}

public protocol WindowSystem {
    @discardableResult
    func refresh() throws -> [WindowSnapshot]
    func discover(windowIDs: Set<WindowID>?) throws -> WindowDiscoverySnapshot
    func apply(_ discovery: WindowDiscoverySnapshot) -> Bool
    func contains(_ id: WindowID) -> Bool
    func focusedWindowID() -> WindowID?
    func frame(for id: WindowID) -> WindowFrame?
    func setPosition(_ point: CGPoint, for id: WindowID) throws
    func setFrame(_ frame: WindowFrame, for id: WindowID) throws
    func focus(_ id: WindowID)
}

public struct WindowDiscoverySnapshot {
    public enum Scope {
        case full
        case windows(Set<WindowID>)
    }

    public let scope: Scope
    public let windows: [WindowSnapshot]
    public let focusedWindowID: WindowID?
    public let frontToBackWindowIDs: [WindowID]

    let handlesByID: [WindowID: WindowHandle]
    let baseRevision: UInt64?

    public init(
        scope: Scope,
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        frontToBackWindowIDs: [WindowID] = []
    ) {
        self.scope = scope
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.frontToBackWindowIDs = frontToBackWindowIDs
        handlesByID = [:]
        baseRevision = nil
    }

    init(
        scope: Scope,
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        frontToBackWindowIDs: [WindowID],
        handlesByID: [WindowID: WindowHandle],
        baseRevision: UInt64
    ) {
        self.scope = scope
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.frontToBackWindowIDs = frontToBackWindowIDs
        self.handlesByID = handlesByID
        self.baseRevision = baseRevision
    }
}

struct WindowFrameTransactionError: Error, CustomStringConvertible {
    let applyError: Error
    let rollbackError: Error

    var description: String {
        "Window frame update failed: \(applyError); frame rollback failed: \(rollbackError)"
    }
}

public extension WindowSystem {
    func discover(windowIDs: Set<WindowID>? = nil) throws -> WindowDiscoverySnapshot {
        let windows = try refresh()
        return WindowDiscoverySnapshot(
            scope: windowIDs.map(WindowDiscoverySnapshot.Scope.windows) ?? .full,
            windows: windowIDs.map { ids in windows.filter { ids.contains($0.id) } } ?? windows,
            focusedWindowID: focusedWindowID(),
            frontToBackWindowIDs: windows.map(\.id)
        )
    }

    func apply(_: WindowDiscoverySnapshot) -> Bool {
        true
    }

    @discardableResult
    func setFrameOrMove(_ targetFrame: WindowFrame, for id: WindowID) throws -> WindowFrame {
        let originalFrame = frame(for: id)
        if originalFrame?.size == targetFrame.size {
            try setPosition(targetFrame.origin, for: id)
            return targetFrame
        }

        do {
            try setFrame(targetFrame, for: id)
            return targetFrame
        } catch {
            // Some windows reject AXSize writes. Their monitor assignment can still succeed
            // by preserving the current size and moving only the origin.
            do {
                try setPosition(targetFrame.origin, for: id)
                return frame(for: id)
                    ?? WindowFrame(origin: targetFrame.origin, size: originalFrame?.size ?? targetFrame.size)
            } catch let positionError {
                try rollbackPartialFrameChange(
                    originalFrame: originalFrame,
                    windowID: id,
                    applyError: positionError
                )
                throw positionError
            }
        }
    }

    private func rollbackPartialFrameChange(
        originalFrame: WindowFrame?,
        windowID: WindowID,
        applyError: Error
    ) throws {
        guard let originalFrame, frame(for: windowID) != originalFrame else {
            throw applyError
        }
        do {
            try setFrame(originalFrame, for: windowID)
        } catch let rollbackError {
            throw WindowFrameTransactionError(
                applyError: applyError,
                rollbackError: rollbackError
            )
        }
    }
}
