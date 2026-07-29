import Foundation

final class WindowContinuityProtector {
    private var entriesByWindowID: [WindowID: WindowContinuityEntry] = [:]
    private var pendingCapturedIdentities: Set<WindowIdentity> = []
    private(set) var diagnostics = WindowContinuityDiagnostics.empty

    var protectedWindowIDs: Set<WindowID> {
        Set(entriesByWindowID.keys)
    }

    var eligibleWindowIDs: Set<WindowID> {
        Set(entriesByWindowID.values.compactMap { $0.isEligible ? $0.identity.windowID : nil })
    }

    var anchorsByWindowID: [WindowID: WindowContinuityAnchor] {
        Dictionary(uniqueKeysWithValues: entriesByWindowID.values.compactMap { entry in
            entry.anchor.map { (entry.identity.windowID, $0) }
        })
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
            deferEligibilityUntilNextDiscovery: true
        )
    }

    func capture(
        windows: [WindowSnapshot],
        topology: DisplayTopologySnapshot,
        state: SpaceState,
        deferEligibilityUntilNextDiscovery: Bool = false
    ) {
        var captured: [WindowIdentity] = []
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
            let frame = state.hiddenFrame(for: window.id) ?? window.frame
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
                isEligible: false
            )
            if deferEligibilityUntilNextDiscovery {
                pendingCapturedIdentities.insert(identity)
            }
            captured.append(identity)
        }
        diagnostics = WindowContinuityDiagnostics(
            captured: captured.diagnostics,
            protectedBeforeResolution: [],
            confirmedRemovedWindowIDs: [],
            suppressedDiscoveredWindowIDs: [],
            protectedAfterResolution: entriesByWindowID.values.identities.diagnostics,
            anchors: entriesByWindowID.values.anchorDiagnostics,
            eligibleWindowIDs: eligibleWindowIDs.sorted(),
            recoveredWindowIDs: [],
            completed: false
        )
    }

    func resolve(
        with discovery: WindowDiscoverySnapshot,
        lifecycle: WindowLifecycleConfirmation
    ) -> WindowContinuityProtectionResolution {
        let newlyCaptured = takePendingCapturedIdentities()
        let protectedBeforeResolution = entriesByWindowID.values.identities.sortedByWindowIdentity
        let discoveredByWindowID = discoveredIdentitiesByWindowID(discovery)
        let classification = classify(
            discoveredByWindowID: discoveredByWindowID,
            lifecycle: lifecycle
        )
        applyConfirmedRemovals(classification.confirmedRemoved)
        updateEligibility(
            discovery: discovery,
            discoveredByWindowID: discoveredByWindowID,
            newlyCaptured: newlyCaptured
        )

        let resolution = WindowContinuityProtectionResolution(
            confirmedRemovedWindowIDs: Set(classification.confirmedRemoved.map(\.windowID)),
            suppressedDiscoveredWindowIDs: Set(
                (classification.terminated + classification.destroyed).map(\.windowID)
            ),
            protectedWindowIDs: protectedWindowIDs,
            eligibleWindowIDs: eligibleWindowIDs
        )
        diagnostics = WindowContinuityDiagnostics(
            captured: newlyCaptured.diagnostics,
            protectedBeforeResolution: protectedBeforeResolution.diagnostics,
            confirmedRemovedWindowIDs: resolution.confirmedRemovedWindowIDs.sorted(),
            suppressedDiscoveredWindowIDs: resolution.suppressedDiscoveredWindowIDs.sorted(),
            protectedAfterResolution: entriesByWindowID.values.identities.diagnostics,
            anchors: entriesByWindowID.values.anchorDiagnostics,
            eligibleWindowIDs: resolution.eligibleWindowIDs.sorted(),
            recoveredWindowIDs: [],
            completed: false
        )
        return resolution
    }

    func completeRecovery(windowIDs: Set<WindowID>) {
        let recovered = windowIDs.intersection(protectedWindowIDs)
        for id in recovered {
            entriesByWindowID.removeValue(forKey: id)
        }
        diagnostics = WindowContinuityDiagnostics(
            captured: [],
            protectedBeforeResolution: diagnostics.protectedAfterResolution,
            confirmedRemovedWindowIDs: [],
            suppressedDiscoveredWindowIDs: [],
            protectedAfterResolution: entriesByWindowID.values.identities.diagnostics,
            anchors: entriesByWindowID.values.anchorDiagnostics,
            eligibleWindowIDs: eligibleWindowIDs.sorted(),
            recoveredWindowIDs: recovered.sorted(),
            completed: !recovered.isEmpty && entriesByWindowID.isEmpty
        )
    }

    func cancel(windowIDs: Set<WindowID>) {
        let cancelled = windowIDs.intersection(protectedWindowIDs)
        for id in windowIDs {
            entriesByWindowID.removeValue(forKey: id)
        }
        guard !cancelled.isEmpty else {
            return
        }
        diagnostics = WindowContinuityDiagnostics(
            captured: [],
            protectedBeforeResolution: diagnostics.protectedAfterResolution,
            confirmedRemovedWindowIDs: [],
            suppressedDiscoveredWindowIDs: [],
            protectedAfterResolution: entriesByWindowID.values.identities.diagnostics,
            anchors: entriesByWindowID.values.anchorDiagnostics,
            eligibleWindowIDs: eligibleWindowIDs.sorted(),
            recoveredWindowIDs: [],
            completed: entriesByWindowID.isEmpty
        )
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
        newlyCaptured: Set<WindowIdentity>
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
            entry.isEligible = discoveredByWindowID[id] == entry.identity
                && !newlyCaptured.contains(entry.identity)
            entriesByWindowID[id] = entry
        }
    }
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
    let eligibleWindowIDs: Set<WindowID>
}

struct WindowContinuityAnchor {
    let space: SpaceID
    let frame: WindowFrame
    let sourceDisplay: DisplaySnapshot
}

private struct WindowContinuityEntry {
    let identity: WindowIdentity
    let anchor: WindowContinuityAnchor?
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

    var anchorDiagnostics: [WindowContinuityAnchorDiagnostics] {
        compactMap { entry in
            entry.anchor.map {
                WindowContinuityAnchorDiagnostics(
                    windowID: entry.identity.windowID,
                    space: $0.space,
                    frame: $0.frame,
                    sourceDisplayID: $0.sourceDisplay.id,
                    sourceDisplayFrame: $0.sourceDisplay.frame
                )
            }
        }.sorted { $0.windowID < $1.windowID }
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

    var diagnostics: [WindowContinuityIdentityDiagnostics] {
        sortedByWindowIdentity.map {
            WindowContinuityIdentityDiagnostics(windowID: $0.windowID, pid: $0.pid)
        }
    }
}

public struct WindowContinuityIdentityDiagnostics {
    public let windowID: WindowID
    public let pid: pid_t
}

public struct WindowContinuityAnchorDiagnostics {
    public let windowID: WindowID
    public let space: SpaceID
    public let frame: WindowFrame
    public let sourceDisplayID: DisplayID
    public let sourceDisplayFrame: CGRect
}

public struct WindowContinuityDiagnostics {
    public let captured: [WindowContinuityIdentityDiagnostics]
    public let protectedBeforeResolution: [WindowContinuityIdentityDiagnostics]
    public let confirmedRemovedWindowIDs: [WindowID]
    public let suppressedDiscoveredWindowIDs: [WindowID]
    public let protectedAfterResolution: [WindowContinuityIdentityDiagnostics]
    public let anchors: [WindowContinuityAnchorDiagnostics]
    public let eligibleWindowIDs: [WindowID]
    public let recoveredWindowIDs: [WindowID]
    public let completed: Bool

    static let empty = WindowContinuityDiagnostics(
        captured: [],
        protectedBeforeResolution: [],
        confirmedRemovedWindowIDs: [],
        suppressedDiscoveredWindowIDs: [],
        protectedAfterResolution: [],
        anchors: [],
        eligibleWindowIDs: [],
        recoveredWindowIDs: [],
        completed: false
    )
}
