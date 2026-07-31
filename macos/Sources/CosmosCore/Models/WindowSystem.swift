import CoreGraphics
import Foundation

public typealias DisplayID = CGDirectDisplayID

public protocol HidePointProviding {
    func hidePoint(for frame: WindowFrame) throws -> CGPoint
    func hidePoint(
        for frame: WindowFrame,
        on display: DisplaySnapshot,
        among displays: [DisplaySnapshot]
    ) -> CGPoint
    func isHidePosition(_ frame: WindowFrame, displays: [DisplaySnapshot]) -> Bool
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

public enum WindowDiscoveryMode: Equatable {
    case normal
    case sessionRecovery
}

public protocol WindowSystem {
    @discardableResult
    func refresh() throws -> [WindowSnapshot]
    func discover(windowIDs: Set<WindowID>?, mode: WindowDiscoveryMode) throws -> WindowDiscoverySnapshot
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
    public let unresolvedWindowIDs: Set<WindowID>

    let handlesByID: [WindowID: WindowHandle]
    let baseRevision: UInt64?

    public init(
        scope: Scope,
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        frontToBackWindowIDs: [WindowID] = [],
        unresolvedWindowIDs: Set<WindowID> = []
    ) {
        self.scope = scope
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.frontToBackWindowIDs = frontToBackWindowIDs
        self.unresolvedWindowIDs = unresolvedWindowIDs
        handlesByID = [:]
        baseRevision = nil
    }

    init(
        scope: Scope,
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        frontToBackWindowIDs: [WindowID],
        unresolvedWindowIDs: Set<WindowID>,
        handlesByID: [WindowID: WindowHandle],
        baseRevision: UInt64
    ) {
        self.scope = scope
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.frontToBackWindowIDs = frontToBackWindowIDs
        self.unresolvedWindowIDs = unresolvedWindowIDs
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

enum WindowFrameWriteObservation: Equatable {
    case exact(actual: WindowFrame)
    case different(actual: WindowFrame)
    case unavailable

    var actualFrame: WindowFrame? {
        switch self {
        case let .exact(actual), let .different(actual):
            actual
        case .unavailable:
            nil
        }
    }
}

public extension WindowSystem {
    func discover(
        windowIDs: Set<WindowID>? = nil,
        mode _: WindowDiscoveryMode = .normal
    ) throws -> WindowDiscoverySnapshot {
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
    internal func setFrameOrMove(
        _ targetFrame: WindowFrame,
        for id: WindowID
    ) throws -> WindowFrameWriteObservation {
        let originalFrame = frame(for: id)
        if originalFrame?.size == targetFrame.size {
            return try setPositionAndObserve(targetFrame.origin, for: id)
        }

        do {
            try setFrame(targetFrame, for: id)
            return observe(targetFrame: targetFrame, for: id)
        } catch {
            // Some windows reject AXSize writes. Their monitor assignment can still succeed
            // by preserving the current size and moving only the origin.
            do {
                return try setPositionAndObserve(targetFrame.origin, for: id)
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

    @discardableResult
    internal func setPositionAndObserve(
        _ targetPosition: CGPoint,
        for id: WindowID
    ) throws -> WindowFrameWriteObservation {
        try setPosition(targetPosition, for: id)
        guard let actualFrame = frame(for: id) else {
            return .unavailable
        }
        return actualFrame.origin == targetPosition
            ? .exact(actual: actualFrame)
            : .different(actual: actualFrame)
    }

    private func observe(
        targetFrame: WindowFrame,
        for id: WindowID
    ) -> WindowFrameWriteObservation {
        guard let actualFrame = frame(for: id) else {
            return .unavailable
        }
        return actualFrame == targetFrame
            ? .exact(actual: actualFrame)
            : .different(actual: actualFrame)
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
