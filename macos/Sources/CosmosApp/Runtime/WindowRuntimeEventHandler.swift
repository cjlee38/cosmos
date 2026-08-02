import CosmosCore
import Foundation

private let windowDiscoveryQueue = DispatchQueue(label: "cosmos.window-discovery", qos: .userInitiated)
final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")
    private let recoveryDiagnostics = WindowRecoveryDiagnostics()

    private let controller: SpaceController
    private let previewService: SwitcherPreviewService
    private let refreshSwitcherContent: () -> Void
    private let refreshStatusSurfaces: () -> Void
    private let scheduleDiscovery: (@escaping () -> Void) -> Void
    private let scheduleApply: (@escaping () -> Void) -> Void
    private let scheduleRecoveryRetry: (TimeInterval, @escaping () -> Void) -> Void
    private var pendingEvents: Set<WindowRuntimeEvent> = []
    private var inFlightEvents: Set<WindowRuntimeEvent> = []
    private var pendingPreviewWindowIDs: Set<WindowID> = []
    private var pendingPreviewSpaceIDs: Set<String> = []
    private var isProcessing = false
    private var observationState = WindowObservationState()
    private var isWakeFocusProtectionActive = false
    private var pendingRecoveryReason: WindowRuntimeRecoveryReason?
    private var recoveryRetryCount = 0
    private var recoveryRetryGeneration: UInt64 = 0
    private var isRecoveryRetryScheduled = false
    private var sessionGeneration: UInt64 = 0
    private var displayGeneration: UInt64 = 0
    private var isDisplayReconfigurationOpen = false
    private var isRecoveryDeferredUntilDisplayEnd = false

    init(
        controller: SpaceController,
        previewService: SwitcherPreviewService,
        refreshSwitcherContent: @escaping () -> Void,
        refreshStatusSurfaces: @escaping () -> Void,
        scheduleDiscovery: @escaping (@escaping () -> Void) -> Void = {
            windowDiscoveryQueue.async(execute: $0)
        },
        scheduleApply: @escaping (@escaping () -> Void) -> Void = {
            DispatchQueue.main.async(execute: $0)
        },
        scheduleRecoveryRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.controller = controller
        self.previewService = previewService
        self.refreshSwitcherContent = refreshSwitcherContent
        self.refreshStatusSurfaces = refreshStatusSurfaces
        self.scheduleDiscovery = scheduleDiscovery
        self.scheduleApply = scheduleApply
        self.scheduleRecoveryRetry = scheduleRecoveryRetry
    }

    var hasPendingContinuityRecovery: Bool {
        pendingRecoveryReason != nil
    }

    func handle(_ events: WindowRuntimeEventBatch) {
        guard isObservationActive else {
            return
        }
        previewService.postponeBackgroundRefresh()
        pendingEvents.formUnion(events.events)
        processNextBatch()
    }

    func displayReconfigurationBegan() {
        guard !isDisplayReconfigurationOpen else {
            return
        }

        isDisplayReconfigurationOpen = true
        displayGeneration &+= 1
        if isObservationActive {
            controller.beginWindowContinuityProtection()
        }
        beginRecovery(.display)
        preserveLifecycleEvidence()
    }

    func displayReconfigurationEnded() {
        guard isDisplayReconfigurationOpen else {
            return
        }
        isDisplayReconfigurationOpen = false
        let shouldResumeRecovery = isRecoveryDeferredUntilDisplayEnd && observationState.isActive
        isRecoveryDeferredUntilDisplayEnd = false
        if shouldResumeRecovery {
            scheduleObservationRecovery()
        }
        processNextBatch()
    }

    func sessionActivityChanged(isActive: Bool) {
        observationSuspensionChanged(.userSession, isSuspended: !isActive)
    }

    func systemSleepChanged(isAwake: Bool) {
        observationSuspensionChanged(.systemSleep, isSuspended: !isAwake)
    }

    func screenLockChanged(isLocked: Bool) {
        observationSuspensionChanged(.screenLock, isSuspended: isLocked)
    }

    private var isObservationActive: Bool {
        observationState.isActive
    }

    private func processNextBatch() {
        guard isObservationActive, !isDisplayReconfigurationOpen, !isProcessing, !pendingEvents.isEmpty else {
            return
        }

        let batchEvents = nextBatchEvents()
        let batch = WindowRuntimeEventBatch(events: batchEvents)
        let generation = WindowRuntimeGeneration(isObservationActive, sessionGeneration, displayGeneration)
        let diagnosticContext = recoveryDiagnostics.beginDiscovery(for: batch)
        pendingEvents.subtract(batchEvents)
        inFlightEvents = batch.events
        isProcessing = true
        scheduleDiscovery { [weak self] in
            guard let self else {
                return
            }
            let discovery = Result {
                try discoverRuntimeWindows(controller: self.controller, batch: batch)
            }
            scheduleApply { [weak self] in
                self?.apply(discovery, for: batch, generation: generation, diagnostics: diagnosticContext)
            }
        }
    }

    private func apply(
        _ discovery: Result<WindowDiscoverySnapshot, Error>,
        for events: WindowRuntimeEventBatch,
        generation: WindowRuntimeGeneration,
        diagnostics: RecoveryDiscoveryContext
    ) {
        let currentGeneration = WindowRuntimeGeneration(isObservationActive, sessionGeneration, displayGeneration)
        guard recoveryDiagnostics.accepts(
            generation, current: currentGeneration, context: diagnostics
        ) else {
            discardDiscovery()
            return
        }

        defer {
            inFlightEvents.removeAll()
            isProcessing = false
            schedulePreviewRefreshIfIdle()
            processNextBatch()
        }

        guard case let .success(acceptedDiscovery) = discovery else {
            if case let .failure(error) = discovery {
                handleWindowUpdateFailure(error, phase: .discovery, for: events, diagnostics)
            }
            return
        }
        do {
            let focusPolicy = events.focusPolicy(
                discovery: acceptedDiscovery,
                previouslyFocusedWindowID: controller.cachedFocusedWindowID(),
                suppressFocus: isWakeFocusProtectionActive
            )
            let change = runtimeExternalWindowChange(events: events, focusPolicy: focusPolicy)
            guard let result = try controller.applyExternalWindowChange(change, discovery: acceptedDiscovery) else {
                pendingEvents.formUnion(events.events)
                log.warning("\(diagnostics.prefix) apply deferred because discovery revision changed")
                return
            }
            recoveryDiagnostics.logApplyResult(result, context: diagnostics)
            refreshPreviews(for: events, result: result)
            updateRecoveryState(for: events, result: result)
            if isWakeFocusProtectionActive, !acceptedDiscovery.windows.isEmpty {
                isWakeFocusProtectionActive = false
            }
            if !result.continuityRecovery.retryableWindowIDs.isEmpty {
                scheduleRecoveryRetryIfNeeded()
            }
            scheduleInitialContinuityVerificationIfNeeded(for: events)
            refreshSwitcherContent()
            refreshStatusSurfaces()
            if case let .switched(windowID, space) = result.focusedWindowSync {
                log.info("Switched to space \(space) for \(windowID)")
            }
        } catch {
            handleWindowUpdateFailure(error, phase: .apply, for: events, diagnostics)
        }
    }

    private func discardDiscovery() {
        inFlightEvents.removeAll()
        isProcessing = false
        processNextBatch()
    }

    private func refreshPreviews(
        for events: WindowRuntimeEventBatch,
        result: ExternalWindowEventResult
    ) {
        let windows = controller.currentWindows()
        let liveWindowIDs = Set(windows.map(\.id))
        let autoAssignedWindowIDs = Set(result.sync.autoAssigned.map(\.0))
        var affectedWindowIDs = events.windowIDs
            .union(result.sync.affectedWindowIDs)
        let focusedWindowID = controller.cachedFocusedWindowID()
        if events.containsFocusChange, let focusedWindowID {
            affectedWindowIDs.insert(focusedWindowID)
        }

        let windowIDs: Set<WindowID>
        let spaceIDs: Set<String>
        if events.needsFullThumbnailRefresh {
            windowIDs = liveWindowIDs
            spaceIDs = Set(controller.spaces)
        } else {
            windowIDs = events.windowIDsNeedingCapture
                .union(autoAssignedWindowIDs)
                .intersection(liveWindowIDs)
            spaceIDs = result.sync.affectedSpaces
                .union(affectedWindowIDs.compactMap(controller.membership(for:)))
        }

        previewService.markWindowThumbnailsDirty(windowIDs)
        pendingPreviewWindowIDs.formUnion(windowIDs)
        pendingPreviewSpaceIDs.formUnion(spaceIDs)
    }

    private func schedulePreviewRefreshIfIdle() {
        guard pendingEvents.isEmpty else {
            return
        }

        previewService.scheduleBackgroundRefresh(
            windowIDs: pendingPreviewWindowIDs,
            spaceIDs: pendingPreviewSpaceIDs
        )
        pendingPreviewWindowIDs.removeAll()
        pendingPreviewSpaceIDs.removeAll()
    }
}

private extension WindowRuntimeEventHandler {
    func observationSuspensionChanged(
        _ reason: WindowObservationSuspension,
        isSuspended: Bool
    ) {
        guard let transition = observationState.set(reason, isSuspended: isSuspended) else {
            return
        }
        if transition.beganSuspension {
            controller.beginWindowContinuityProtection()
            isWakeFocusProtectionActive = true
        }
        if isSuspended {
            beginRecovery(reason.recoveryReason)
        }

        WindowObservationDiagnostics.logSuspensionChanged(
            reason: reason,
            isSuspended: isSuspended,
            activeReasons: transition.activeReasons
        )
        sessionGeneration &+= 1
        preserveLifecycleEvidence()
        if transition.isActive {
            if isDisplayReconfigurationOpen {
                isRecoveryDeferredUntilDisplayEnd = true
            } else {
                scheduleObservationRecovery()
            }
        }
    }

    func scheduleObservationRecovery() {
        let kind = pendingRecoveryReason?.eventKind ?? .sessionResumed
        handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: kind, windowID: nil)
        ]))
    }

    func nextBatchEvents() -> Set<WindowRuntimeEvent> {
        let recoveryEvents = pendingEvents.filter { $0.kind == .continuityRecovery }
        return recoveryEvents.isEmpty ? pendingEvents : recoveryEvents
    }

    func preserveLifecycleEvidence() {
        pendingEvents = pendingEvents
            .union(inFlightEvents)
            .filter(\.kind.mustSurviveObservationSuspension)
    }

    func appendContinuityRecovery() {
        pendingEvents.insert(WindowRuntimeEvent(kind: .continuityRecovery, windowID: nil))
    }

    func scheduleInitialContinuityVerificationIfNeeded(
        for events: WindowRuntimeEventBatch
    ) {
        guard events.events.contains(where: { $0.kind == .displayChanged })
        else {
            return
        }
        appendContinuityRecovery()
    }

    func handleWindowUpdateFailure(
        _ error: Error,
        phase: WindowUpdateFailurePhase,
        for events: WindowRuntimeEventBatch,
        _ diagnostics: RecoveryDiscoveryContext
    ) {
        scheduleInitialContinuityVerificationIfNeeded(for: events)
        if events.containsRecoveryRequest {
            scheduleRecoveryRetryIfNeeded()
        }
        switch phase {
        case .discovery:
            recoveryDiagnostics.logDiscoveryFailed(error, context: diagnostics)
        case .apply:
            recoveryDiagnostics.logApplyFailed(error, context: diagnostics)
        }
    }

    func beginRecovery(_ reason: WindowRuntimeRecoveryReason) {
        if pendingRecoveryReason?.requiresDisplayRecovery != true
            || reason.requiresDisplayRecovery {
            pendingRecoveryReason = reason
        }
        recoveryRetryCount = 0
        recoveryRetryGeneration &+= 1
        isRecoveryRetryScheduled = false
        recoveryDiagnostics.beginRecovery(reason: reason)
    }

    func updateRecoveryState(
        for events: WindowRuntimeEventBatch,
        result: ExternalWindowEventResult
    ) {
        guard result.continuityRecovery.isPending else {
            pendingRecoveryReason = nil
            recoveryRetryCount = 0
            recoveryRetryGeneration &+= 1
            isRecoveryRetryScheduled = false
            removeQueuedRecoveryRequests()
            recoveryDiagnostics.complete()
            return
        }
        if pendingRecoveryReason == nil {
            pendingRecoveryReason = events.containsDisplayChange ? .display : .userSession
        }
    }

    func scheduleRecoveryRetryIfNeeded() {
        guard pendingRecoveryReason != nil,
              isObservationActive,
              !isRecoveryRetryScheduled
        else {
            return
        }
        guard recoveryRetryCount < maximumRecoveryRetryCount else {
            recoveryDiagnostics.logRetryExhausted(count: recoveryRetryCount)
            return
        }
        let delay = recoveryRetryDelay * TimeInterval(1 << recoveryRetryCount)
        recoveryRetryCount += 1
        isRecoveryRetryScheduled = true
        let generation = recoveryRetryGeneration
        scheduleRecoveryRetry(delay) { [weak self] in
            guard let self,
                  generation == recoveryRetryGeneration
            else {
                return
            }
            isRecoveryRetryScheduled = false
            guard isObservationActive, pendingRecoveryReason != nil else {
                return
            }
            scheduleObservationRecovery()
        }
    }

    func removeQueuedRecoveryRequests() {
        pendingEvents.subtract(pendingEvents.filter(\.kind.isRecoveryRequest))
    }
}
