import CoreGraphics
import Foundation

public final class WindowRegistry: WindowSystem {
    private let axClient: AXClient
    private let lock = NSLock()
    private var handlesByID: [WindowID: WindowHandle] = [:]
    private var revision: UInt64 = 0

    public init(axClient: AXClient) {
        self.axClient = axClient
    }

    @discardableResult
    public func refresh() throws -> [WindowSnapshot] {
        while true {
            let discovery = try discover(windowIDs: nil, mode: .normal)
            if apply(discovery) {
                return discovery.windows
            }
        }
    }

    public func discover(
        windowIDs: Set<WindowID>?,
        mode: WindowDiscoveryMode
    ) throws -> WindowDiscoverySnapshot {
        let (baseRevision, cachedHandlesByID) = currentRegistryState()
        var handles: [WindowHandle]
        var unresolvedWindowIDs: Set<WindowID> = []
        let scope: WindowDiscoverySnapshot.Scope
        if let windowIDs {
            handles = windowIDs.compactMap { cachedHandlesByID[$0] }
            scope = .windows(windowIDs)
        } else {
            handles = try axClient.enumerateWindows()
            scope = .full
            if mode == .sessionRecovery {
                let discoveredWindowIDs = Set(handles.map(\.id))
                for handle in cachedHandlesByID.values where !discoveredWindowIDs.contains(handle.id) {
                    switch axClient.validity(of: handle) {
                    case .valid:
                        handles.append(handle)
                    case .invalid:
                        break
                    case .unresolved:
                        handles.append(handle)
                        unresolvedWindowIDs.insert(handle.id)
                    }
                }
            }
        }
        let frontToBackIndex = CGWindowStackOrder.frontToBackIndexByWindowID()
        let windows = handles
            .filter { !unresolvedWindowIDs.contains($0.id) }
            .map(axClient.snapshot)
            .sorted {
                Self.sortByFrontToBackOrder($0, $1, frontToBackIndex: frontToBackIndex)
            }
        let frontToBackWindowIDs = frontToBackIndex.keys.sorted {
            frontToBackIndex[$0, default: .max] < frontToBackIndex[$1, default: .max]
        }
        return WindowDiscoverySnapshot(
            scope: scope,
            windows: windows,
            focusedWindowID: axClient.focusedWindowID(),
            frontToBackWindowIDs: frontToBackWindowIDs,
            unresolvedWindowIDs: unresolvedWindowIDs,
            handlesByID: Dictionary(uniqueKeysWithValues: handles.map { ($0.id, $0) }),
            baseRevision: baseRevision
        )
    }

    public func apply(_ discovery: WindowDiscoverySnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard discovery.baseRevision == revision else {
            return false
        }
        applyLocked(discovery)
        return true
    }

    func handle(for id: WindowID) -> WindowHandle? {
        lock.lock()
        defer { lock.unlock() }
        return handlesByID[id]
    }

    public func contains(_ id: WindowID) -> Bool {
        handle(for: id) != nil
    }

    public func focusedWindowID() -> WindowID? {
        axClient.focusedWindowID()
    }

    public func frame(for id: WindowID) -> WindowFrame? {
        guard let handle = handle(for: id) else {
            return nil
        }
        return axClient.frame(for: handle.axWindow)
    }

    public func setPosition(_ point: CGPoint, for id: WindowID) throws {
        guard let handle = handle(for: id) else {
            throw SpaceError.windowNotFound(id)
        }
        try axClient.setPosition(point, for: handle.axWindow)
        advanceRevision()
    }

    public func setFrame(_ frame: WindowFrame, for id: WindowID) throws {
        guard let handle = handle(for: id) else {
            throw SpaceError.windowNotFound(id)
        }
        try axClient.setFrame(frame, for: handle.axWindow)
        advanceRevision()
    }

    public func focus(_ id: WindowID) {
        guard let handle = handle(for: id) else {
            return
        }
        axClient.focus(handle)
        advanceRevision()
    }

    private func currentRegistryState() -> (revision: UInt64, handlesByID: [WindowID: WindowHandle]) {
        lock.lock()
        defer { lock.unlock() }
        return (revision, handlesByID)
    }

    private func advanceRevision() {
        lock.lock()
        defer { lock.unlock() }
        revision &+= 1
    }

    private func applyLocked(_ discovery: WindowDiscoverySnapshot) {
        if case .full = discovery.scope {
            handlesByID = discovery.handlesByID
        }
        revision &+= 1
    }

    static func sortByFrontToBackOrder(
        _ lhs: WindowSnapshot,
        _ rhs: WindowSnapshot,
        frontToBackIndex: [WindowID: Int]
    ) -> Bool {
        switch (frontToBackIndex[lhs.id], frontToBackIndex[rhs.id]) {
        case let (lhsIndex?, rhsIndex?):
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.id < rhs.id
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return fallbackWindowOrder(lhs, rhs)
        }
    }

    private static func fallbackWindowOrder(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        if lhs.app.name == rhs.app.name {
            return lhs.id < rhs.id
        }
        return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
    }
}

private enum CGWindowStackOrder {
    static func frontToBackIndexByWindowID() -> [WindowID: Int] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var indexByID: [WindowID: Int] = [:]
        for (index, info) in rawList.enumerated() {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber
            else {
                continue
            }

            indexByID[WindowID(number.uint32Value)] = index
        }
        return indexByID
    }
}
