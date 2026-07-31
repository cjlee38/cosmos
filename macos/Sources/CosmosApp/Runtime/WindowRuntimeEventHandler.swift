import CosmosCore
import Foundation

private let windowDiscoveryQueue = DispatchQueue(
    label: "cosmos.window-discovery",
    qos: .userInitiated
)
private let maximumRecoveryRetryCount = 3
private let recoveryRetryDelay: TimeInterval = 0.25

final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")

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
    private var isSessionActive = true
    private var isSystemAwake = true
    private var isWakeFocusProtectionActive = false
    private var pendingRecoveryReason: WindowRuntimeRecoveryReason?
    private var recoveryRetryCount = 0
    private var recoveryRetryGeneration: UInt64 = 0
    private var isRecoveryRetryScheduled = false
    private var sessionGeneration: UInt64 = 0
    private var displayGeneration: UInt64 = 0
    private var isDisplayReconfigurationOpen = false

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
        controller.beginWindowContinuityProtection()
        beginRecovery(.display)
        preserveLifecycleEvidence()
    }

    func displayReconfigurationEnded() {
        isDisplayReconfigurationOpen = false
    }

    func sessionActivityChanged(isActive: Bool) {
        guard isSessionActive != isActive else {
            return
        }

        if !isActive {
            controller.beginWindowContinuityProtection()
            isWakeFocusProtectionActive = true
            beginRecovery(.session)
        }
        isSessionActive = isActive
        sessionGeneration &+= 1
        preserveLifecycleEvidence()
        if isObservationActive {
            scheduleObservationRecovery()
        }
    }

    func systemSleepChanged(isAwake: Bool) {
        guard isSystemAwake != isAwake else {
            return
        }

        if !isAwake {
            controller.beginWindowContinuityProtection()
            isWakeFocusProtectionActive = true
            beginRecovery(.display)
        }
        isSystemAwake = isAwake
        sessionGeneration &+= 1
        preserveLifecycleEvidence()
        if isObservationActive {
            scheduleObservationRecovery()
        }
    }

    private var isObservationActive: Bool {
        isSessionActive && isSystemAwake
    }

    private func processNextBatch() {
        guard isObservationActive, !isProcessing, !pendingEvents.isEmpty else {
            return
        }

        let batchEvents = nextBatchEvents()
        let batch = WindowRuntimeEventBatch(events: batchEvents)
        let generation = WindowRuntimeGeneration(
            session: sessionGeneration,
            display: displayGeneration
        )
        pendingEvents.subtract(batchEvents)
        inFlightEvents = batch.events
        isProcessing = true
        scheduleDiscovery { [weak self] in
            guard let self else {
                return
            }
            let discovery = Result {
                try self.controller.discoverWindows(
                    windowIDs: batch.discoveryWindowIDs,
                    mode: batch.usesSessionRecoveryDiscovery ? .sessionRecovery : .normal
                )
            }
            scheduleApply { [weak self] in
                self?.apply(discovery, for: batch, generation: generation)
            }
        }
    }

    private func apply(
        _ discovery: Result<WindowDiscoverySnapshot, Error>,
        for events: WindowRuntimeEventBatch,
        generation: WindowRuntimeGeneration
    ) {
        guard isObservationActive,
              generation.session == sessionGeneration,
              generation.display == displayGeneration
        else {
            discardDiscovery()
            return
        }

        defer {
            inFlightEvents.removeAll()
            isProcessing = false
            schedulePreviewRefreshIfIdle()
            processNextBatch()
        }

        do {
            let discovery = try discovery.get()
            let focusPolicy = focusPolicy(for: events, discovery: discovery)
            guard let result = try controller.applyExternalWindowChange(
                ExternalWindowChange(
                    displayConfigurationChanged: events.containsDisplayChange,
                    focusPolicy: focusPolicy,
                    terminatedApplicationPIDs: events.terminatedApplicationPIDs,
                    destroyedWindowIDs: events.destroyedWindowIDs,
                    userMovedWindowIDs: events.userMovedWindowIDs
                ),
                discovery: discovery
            ) else {
                pendingEvents.formUnion(events.events)
                return
            }
            refreshPreviews(for: events, result: result)
            updateRecoveryState(for: events, result: result)
            if isWakeFocusProtectionActive, !discovery.windows.isEmpty {
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
            handleDiscoveryFailure(error, for: events)
        }
    }

    private func discardDiscovery() {
        inFlightEvents.removeAll()
        isProcessing = false
        processNextBatch()
    }

    private func focusPolicy(
        for events: WindowRuntimeEventBatch,
        discovery: WindowDiscoverySnapshot
    ) -> ExternalWindowFocusPolicy {
        if isWakeFocusProtectionActive {
            return .never
        }
        if events.containsApplicationActivation {
            return .always
        }
        if events.shouldFollowVisibleFocusedWindow(
            focusedWindowID: discovery.focusedWindowID,
            previouslyFocusedWindowID: controller.cachedFocusedWindowID(),
            liveWindowIDs: Set(discovery.windows.map(\.id))
        ) {
            return .visibleFocusedWindow
        }
        return .never
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

    func handleDiscoveryFailure(
        _ error: Error,
        for events: WindowRuntimeEventBatch
    ) {
        scheduleInitialContinuityVerificationIfNeeded(for: events)
        if events.containsRecoveryRequest {
            scheduleRecoveryRetryIfNeeded()
        }
        log.error("Window update failed: \(String(describing: error))")
    }

    func beginRecovery(_ reason: WindowRuntimeRecoveryReason) {
        if pendingRecoveryReason != .display || reason == .display {
            pendingRecoveryReason = reason
        }
        recoveryRetryCount = 0
        recoveryRetryGeneration &+= 1
        isRecoveryRetryScheduled = false
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
            return
        }
        if pendingRecoveryReason == nil {
            pendingRecoveryReason = events.containsDisplayChange ? .display : .session
        }
    }

    func scheduleRecoveryRetryIfNeeded() {
        guard pendingRecoveryReason != nil,
              isObservationActive,
              !isRecoveryRetryScheduled,
              recoveryRetryCount < maximumRecoveryRetryCount
        else {
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

private struct WindowRuntimeGeneration {
    let session: UInt64
    let display: UInt64
}
