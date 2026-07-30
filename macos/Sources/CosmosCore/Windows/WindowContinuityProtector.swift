import Foundation

final class WindowContinuityProtector {
    private var entriesByWindowID: [WindowID: WindowContinuityEntry] = [:]
    private var pendingCapturedIdentities: Set<WindowIdentity> = []

    var protectedWindowIDs: Set<WindowID> {
        Set(entriesByWindowID.keys)
    }

    var recoveryPlan: WindowContinuityRecoveryPlan {
        let eligibleEntries = entriesByWindowID.values.filter(\.isEligible)
        return WindowContinuityRecoveryPlan(
            windowIDs: Set(eligibleEntries.map(\.identity.windowID)),
            anchorsByWindowID: Dictionary(
                uniqueKeysWithValues: eligibleEntries.compactMap { entry in
                    entry.anchor.map { (entry.identity.windowID, $0) }
                }
            )
        )
    }

    func captureIfDisplayContinuityWasLost(
        previousTopology: DisplayTopologySnapshot,
        currentTopology: DisplayTopologySnapshot,
        windows: [WindowSnapshot],
        state: SpaceState
    ) {
        let previousDisplayIDs = Set(previousTopology.displays.map(\.id))
        let currentDisplayIDs = Set(currentTopology.displays.map(\.id))
        guard !previousDisplayIDs.isEmpty,
              !currentDisplayIDs.isEmpty,
              previousDisplayIDs.isDisjoint(with: currentDisplayIDs)
        else {
            return
        }

        capture(
            windows: windows,
            topology: previousTopology,
            state: state,
            phase: .afterDiscovery
        )
    }

    func capture(
        windows: [WindowSnapshot],
        topology: DisplayTopologySnapshot,
        state: SpaceState,
        phase: WindowContinuityCapturePhase
    ) {
        for window in windows {
            guard let space = state.membership(for: window.id),
                  entriesByWindowID[window.id] == nil
            else {
                continue
            }
            let identity = window.identity
            let sourceSlot = state.monitorSlot(
                for: space,
                availableMonitorSlots: topology.availableMonitorSlots
            )
            let sourceDisplay = topology.monitorSlots.first {
                $0.slot == sourceSlot
            }?.display
            let hiddenFrame = state.hiddenFrame(for: window.id)
            let frame = hiddenFrame ?? window.frame
            let anchor = frame.flatMap { frame in
                sourceDisplay.map {
                    WindowContinuityAnchor(
                        space: space,
                        frame: frame,
                        sourceDisplay: $0
                    )
                }
            }
            entriesByWindowID[window.id] = WindowContinuityEntry(
                identity: identity,
                anchor: anchor,
                capturedObservedFrame: window.frame,
                wasMinimized: window.isMinimized,
                wasHiddenByCosmos: hiddenFrame != nil,
                isEligible: false
            )
            if phase == .afterDiscovery {
                pendingCapturedIdentities.insert(identity)
            }
        }
    }

    func resolve(
        with discovery: WindowDiscoverySnapshot,
        lifecycle: WindowLifecycleConfirmation,
        topology: DisplayTopologySnapshot
    ) -> WindowContinuityProtectionResolution {
        let newlyCaptured = takePendingCapturedIdentities()
        let discoveredByWindowID = discoveredIdentitiesByWindowID(discovery)
        let classification = classify(
            discoveredByWindowID: discoveredByWindowID,
            lifecycle: lifecycle
        )
        applyConfirmedRemovals(classification.confirmedRemoved)
        updateEligibility(
            discovery: discovery,
            discoveredByWindowID: discoveredByWindowID,
            newlyCaptured: newlyCaptured,
            topology: topology
        )

        return WindowContinuityProtectionResolution(
            confirmedRemovedWindowIDs: Set(classification.confirmedRemoved.map(\.windowID)),
            suppressedDiscoveredWindowIDs: Set(
                (classification.terminated + classification.destroyed).map(\.windowID)
            ),
            protectedWindowIDs: protectedWindowIDs
        )
    }

    func completeRecovery(windowIDs: Set<WindowID>) {
        for id in windowIDs.intersection(protectedWindowIDs) {
            entriesByWindowID.removeValue(forKey: id)
        }
    }

    func cancel(windowIDs: Set<WindowID>) {
        for id in windowIDs {
            entriesByWindowID.removeValue(forKey: id)
        }
    }

    private func takePendingCapturedIdentities() -> Set<WindowIdentity> {
        defer { pendingCapturedIdentities.removeAll() }
        return pendingCapturedIdentities
    }

    private func discoveredIdentitiesByWindowID(
        _ discovery: WindowDiscoverySnapshot
    ) -> [WindowID: WindowIdentity] {
        Dictionary(
            discovery.windows.map { ($0.id, $0.identity) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func classify(
        discoveredByWindowID: [WindowID: WindowIdentity],
        lifecycle: WindowLifecycleConfirmation
    ) -> WindowContinuityClassification {
        var classification = WindowContinuityClassification()
        for identity in entriesByWindowID.values.identities.sortedByWindowIdentity {
            let discoveredIdentity = discoveredByWindowID[identity.windowID]
            if let discoveredIdentity, discoveredIdentity != identity {
                classification.replaced.append(identity)
            } else if lifecycle.terminatedApplicationPIDs.contains(identity.pid) {
                classification.terminated.append(identity)
            } else if lifecycle.destroyedWindowIDs.contains(identity.windowID) {
                classification.destroyed.append(identity)
            }
        }
        return classification
    }

    private func applyConfirmedRemovals(_ identities: [WindowIdentity]) {
        for identity in identities {
            entriesByWindowID.removeValue(forKey: identity.windowID)
        }
    }

    private func updateEligibility(
        discovery: WindowDiscoverySnapshot,
        discoveredByWindowID: [WindowID: WindowIdentity],
        newlyCaptured: Set<WindowIdentity>,
        topology: DisplayTopologySnapshot
    ) {
        let inspectedWindowIDs: Set<WindowID> = switch discovery.scope {
        case .full:
            protectedWindowIDs
        case let .windows(ids):
            ids.intersection(protectedWindowIDs)
        }

        for id in inspectedWindowIDs {
            guard var entry = entriesByWindowID[id] else {
                continue
            }
            let discoveredWindow = discovery.windows.first { $0.id == id }
            if discoveredByWindowID[id] != entry.identity {
                entry.isEligible = false
            } else if newlyCaptured.contains(entry.identity) {
                entry.isEligible = false
            } else {
                entry.isEligible = isReady(
                    entry: entry,
                    discoveredWindow: discoveredWindow,
                    topology: topology
                )
            }
            entriesByWindowID[id] = entry
        }
    }

    private func isReady(
        entry: WindowContinuityEntry,
        discoveredWindow: WindowSnapshot?,
        topology: DisplayTopologySnapshot
    ) -> Bool {
        guard let discoveredWindow else {
            return false
        }
        guard let anchor = entry.anchor else {
            return true
        }
        if entry.wasMinimized {
            return true
        }
        if entry.wasHiddenByCosmos {
            return true
        }
        if let currentSourceDisplay = topology.displays.first(where: {
            $0.id == anchor.sourceDisplay.id
        }) {
            if hasEquivalentGeometry(currentSourceDisplay, anchor.sourceDisplay) {
                return true
            }
            if let capturedFrame = entry.capturedObservedFrame,
               let observedFrame = discoveredWindow.frame,
               approximatelyEqual(capturedFrame, observedFrame),
               currentSourceDisplay.frame.contains(CGRect(
                   origin: capturedFrame.origin,
                   size: capturedFrame.size
               )) {
                return true
            }
        }
        if topology.displays.contains(where: {
            hasEquivalentGeometry($0, anchor.sourceDisplay)
        }) {
            return true
        }
        guard let capturedFrame = entry.capturedObservedFrame,
              let observedFrame = discoveredWindow.frame
        else {
            return false
        }
        return !approximatelyEqual(capturedFrame, observedFrame)
    }
}

private func hasEquivalentGeometry(
    _ lhs: DisplaySnapshot,
    _ rhs: DisplaySnapshot
) -> Bool {
    approximatelyEqual(lhs.frame, rhs.frame)
        && approximatelyEqual(lhs.visibleFrame, rhs.visibleFrame)
}

private func approximatelyEqual(_ lhs: WindowFrame, _ rhs: WindowFrame) -> Bool {
    approximatelyEqual(lhs.origin.x, rhs.origin.x)
        && approximatelyEqual(lhs.origin.y, rhs.origin.y)
        && approximatelyEqual(lhs.size.width, rhs.size.width)
        && approximatelyEqual(lhs.size.height, rhs.size.height)
}

private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    approximatelyEqual(lhs.origin.x, rhs.origin.x)
        && approximatelyEqual(lhs.origin.y, rhs.origin.y)
        && approximatelyEqual(lhs.size.width, rhs.size.width)
        && approximatelyEqual(lhs.size.height, rhs.size.height)
}

private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) <= 0.5
}

struct WindowLifecycleConfirmation {
    let terminatedApplicationPIDs: Set<pid_t>
    let destroyedWindowIDs: Set<WindowID>

    static let empty = WindowLifecycleConfirmation(
        terminatedApplicationPIDs: [],
        destroyedWindowIDs: []
    )
}

struct WindowContinuityProtectionResolution {
    let confirmedRemovedWindowIDs: Set<WindowID>
    let suppressedDiscoveredWindowIDs: Set<WindowID>
    let protectedWindowIDs: Set<WindowID>
}

struct WindowContinuityAnchor {
    let space: SpaceID
    let frame: WindowFrame
    let sourceDisplay: DisplaySnapshot
}

struct WindowContinuityRecoveryPlan {
    let windowIDs: Set<WindowID>
    let anchorsByWindowID: [WindowID: WindowContinuityAnchor]
}

enum WindowContinuityCapturePhase {
    case beforeDiscovery
    case afterDiscovery
}

private struct WindowContinuityEntry {
    let identity: WindowIdentity
    let anchor: WindowContinuityAnchor?
    let capturedObservedFrame: WindowFrame?
    let wasMinimized: Bool
    let wasHiddenByCosmos: Bool
    var isEligible: Bool
}

private struct WindowIdentity: Equatable, Hashable {
    let windowID: WindowID
    let pid: pid_t
}

private struct WindowContinuityClassification {
    var terminated: [WindowIdentity] = []
    var destroyed: [WindowIdentity] = []
    var replaced: [WindowIdentity] = []

    var confirmedRemoved: [WindowIdentity] {
        terminated + destroyed + replaced
    }
}

private extension WindowSnapshot {
    var identity: WindowIdentity {
        WindowIdentity(windowID: id, pid: app.pid)
    }
}

private extension Sequence<WindowContinuityEntry> {
    var identities: [WindowIdentity] {
        map(\.identity)
    }
}

private extension Sequence<WindowIdentity> {
    var sortedByWindowIdentity: [WindowIdentity] {
        sorted {
            if $0.windowID != $1.windowID {
                return $0.windowID < $1.windowID
            }
            return $0.pid < $1.pid
        }
    }
}
