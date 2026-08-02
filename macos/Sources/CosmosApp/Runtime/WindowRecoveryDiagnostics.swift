import CosmosCore
import Foundation

final class WindowRecoveryDiagnostics {
    private let log = Log(category: "window-events")
    private var sequence: UInt64 = 0
    private var activeRecoveryID: UInt64?
    private var attempt = 0

    func beginRecovery(reason: WindowRuntimeRecoveryReason) {
        if let activeRecoveryID {
            log.info("[recovery:\(activeRecoveryID)] lifecycle merged reason=\(reason)")
            return
        }
        sequence &+= 1
        activeRecoveryID = sequence
        attempt = 0
        log.warning("[recovery:\(sequence)] protection started reason=\(reason)")
    }

    func beginDiscovery(for batch: WindowRuntimeEventBatch) -> RecoveryDiscoveryContext {
        let recoveryID = activeRecoveryID
        let discoveryAttempt: Int?
        if batch.containsRecoveryRequest, let recoveryID {
            attempt += 1
            discoveryAttempt = attempt
            log.info("[recovery:\(recoveryID) attempt:\(attempt)] started")
        } else {
            discoveryAttempt = nil
        }
        return RecoveryDiscoveryContext(recoveryID: recoveryID, attempt: discoveryAttempt)
    }

    func accepts(
        _ expected: WindowRuntimeGeneration,
        current: WindowRuntimeGeneration,
        context: RecoveryDiscoveryContext
    ) -> Bool {
        guard !current.active
            || expected.session != current.session
            || expected.display != current.display
        else {
            return true
        }
        if context.recoveryID != nil {
            log.warning(
                "\(context.prefix) discovery discarded "
                    + "observationActive=\(current.active) "
                    + "sessionGeneration=\(expected.session)->\(current.session) "
                    + "displayGeneration=\(expected.display)->\(current.display)"
            )
        }
        return false
    }

    func logDiscoveryFailed(_ error: Error, context: RecoveryDiscoveryContext) {
        log.error("\(context.prefix) discovery failed error=\(String(describing: error))")
    }

    func logApplyResult(_ result: ExternalWindowEventResult, context: RecoveryDiscoveryContext) {
        for change in result.sync.membershipChanges.sorted(by: { $0.windowID < $1.windowID }) {
            log.warning(
                "\(context.prefix) membership changed window=\(change.windowID) "
                    + "from=\(change.previousSpace ?? "nil") to=\(change.space ?? "nil")"
            )
        }
        guard context.recoveryID != nil else {
            return
        }
        let recovery = result.continuityRecovery
        for windowID in recovery.failedWindowIDs.sorted() {
            let retryable = recovery.retryableWindowIDs.contains(windowID)
            let reason = recovery.failureReasonsByWindowID[windowID] ?? "unknown"
            log.error(
                "\(context.prefix) recovery failed window=\(windowID) "
                    + "retryable=\(retryable) error=\(reason)"
            )
        }
    }

    func logApplyFailed(_ error: Error, context: RecoveryDiscoveryContext) {
        log.error("\(context.prefix) apply failed error=\(String(describing: error))")
    }

    func logRetryExhausted(count: Int) {
        guard let activeRecoveryID else {
            return
        }
        log.error("[recovery:\(activeRecoveryID)] retry exhausted count=\(count)")
    }

    func complete() {
        guard let activeRecoveryID else {
            return
        }
        log.info("[recovery:\(activeRecoveryID)] completed")
        self.activeRecoveryID = nil
    }
}
