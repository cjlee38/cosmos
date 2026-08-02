import CosmosCore
import Foundation

let maximumRecoveryRetryCount = 3
let recoveryRetryDelay: TimeInterval = 0.25

enum WindowObservationDiagnostics {
    private static let log = Log(category: "window-events")

    static func logSuspensionChanged(
        reason: WindowObservationSuspension,
        isSuspended: Bool,
        activeReasons: Set<WindowObservationSuspension>
    ) {
        let reasons = activeReasons.map(\.description).sorted().joined(separator: ",")
        log.warning(
            "observation \(isSuspended ? "suspended" : "resumed") "
                + "reason=\(reason) activeReasons=[\(reasons)]"
        )
    }
}

struct WindowRuntimeGeneration {
    let active: Bool
    let session: UInt64
    let display: UInt64

    init(_ active: Bool, _ session: UInt64, _ display: UInt64) {
        self.active = active
        self.session = session
        self.display = display
    }
}

struct RecoveryDiscoveryContext {
    let recoveryID: UInt64?
    let attempt: Int?

    var prefix: String {
        guard let recoveryID else {
            return "[window-update]"
        }
        if let attempt {
            return "[recovery:\(recoveryID) attempt:\(attempt)]"
        }
        return "[recovery:\(recoveryID)]"
    }
}

enum WindowUpdateFailurePhase {
    case discovery
    case apply
}

func discoverRuntimeWindows(
    controller: SpaceController,
    batch: WindowRuntimeEventBatch
) throws -> WindowDiscoverySnapshot {
    try controller.discoverWindows(
        windowIDs: batch.discoveryWindowIDs,
        mode: batch.usesSessionRecoveryDiscovery ? .sessionRecovery : .normal
    )
}

func runtimeExternalWindowChange(
    events: WindowRuntimeEventBatch,
    focusPolicy: ExternalWindowFocusPolicy
) -> ExternalWindowChange {
    ExternalWindowChange(
        displayConfigurationChanged: events.containsDisplayChange,
        focusPolicy: focusPolicy,
        terminatedApplicationPIDs: events.terminatedApplicationPIDs,
        destroyedWindowIDs: events.destroyedWindowIDs,
        userMovedWindowIDs: events.userMovedWindowIDs
    )
}
