import Foundation

final class WindowContinuityProtector {
    private var identitiesByWindowID: [WindowID: WindowIdentity] = [:]
    private var pendingCapturedIdentities: Set<WindowIdentity> = []

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

        for window in windows {
            guard state.membership(for: window.id) != nil,
                  identitiesByWindowID[window.id] == nil
            else {
                continue
            }
            let identity = window.identity
            identitiesByWindowID[window.id] = identity
            pendingCapturedIdentities.insert(identity)
        }
    }

    func resolve(
        with discovery: WindowDiscoverySnapshot,
        lifecycle: WindowLifecycleConfirmation
    ) -> WindowContinuityProtectionResolution {
        let newlyCaptured = takePendingCapturedIdentities()

        let discoveredByWindowID = discoveredIdentitiesByWindowID(discovery)
        let classification = classify(
            discoveredByWindowID: discoveredByWindowID,
            lifecycle: lifecycle
        )
        applyConfirmedRemovals(classification.confirmedRemoved)
        let replacementIdentities = protectReplacements(
            classification.replaced,
            discoveredByWindowID: discoveredByWindowID
        )

        finishIfAllRemainingIdentitiesArePresent(
            discoveryScope: discovery.scope,
            discoveredByWindowID: discoveredByWindowID,
            newlyCaptured: newlyCaptured.union(replacementIdentities)
        )
        return WindowContinuityProtectionResolution(
            confirmedRemovedWindowIDs: Set(classification.confirmedRemoved.map(\.windowID)),
            suppressedDiscoveredWindowIDs: Set(
                (classification.terminated + classification.destroyed).map(\.windowID)
            ),
            protectedWindowIDs: Set(identitiesByWindowID.keys)
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
        for identity in identitiesByWindowID.values.sortedByWindowIdentity {
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
            identitiesByWindowID.removeValue(forKey: identity.windowID)
        }
    }

    private func protectReplacements(
        _ replaced: [WindowIdentity],
        discoveredByWindowID: [WindowID: WindowIdentity]
    ) -> Set<WindowIdentity> {
        Set(replaced.compactMap { identity in
            guard let replacement = discoveredByWindowID[identity.windowID] else {
                return nil
            }
            identitiesByWindowID[replacement.windowID] = replacement
            return replacement
        })
    }

    private func finishIfAllRemainingIdentitiesArePresent(
        discoveryScope: WindowDiscoverySnapshot.Scope,
        discoveredByWindowID: [WindowID: WindowIdentity],
        newlyCaptured: Set<WindowIdentity>
    ) {
        guard case .full = discoveryScope else {
            return
        }
        guard identitiesByWindowID.values.allSatisfy({
            discoveredByWindowID[$0.windowID] == $0 && !newlyCaptured.contains($0)
        }) else {
            return
        }
        identitiesByWindowID.removeAll()
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
