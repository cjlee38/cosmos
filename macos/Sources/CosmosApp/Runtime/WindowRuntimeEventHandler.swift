import CosmosCore
import Foundation

private let windowDiscoveryQueue = DispatchQueue(
    label: "cosmos.window-discovery",
    qos: .userInitiated
)

final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")

    private let controller: SpaceController
    private let previewService: SwitcherPreviewService
    private let refreshSwitcherContent: () -> Void
    private let refreshStatusSurfaces: () -> Void
    private let scheduleDiscovery: (@escaping () -> Void) -> Void
    private let scheduleApply: (@escaping () -> Void) -> Void
    private var pendingEvents: Set<WindowRuntimeEvent> = []
    private var inFlightEvents: Set<WindowRuntimeEvent> = []
    private var pendingPreviewWindowIDs: Set<WindowID> = []
    private var pendingPreviewSpaceIDs: Set<String> = []
    private var isProcessing = false
    private var isSessionActive = true
    private var isSystemAwake = true
    private(set) var hasPendingContinuityRecovery = false
    private var hasRetriedContinuityRecovery = false
    private var sessionGeneration: UInt64 = 0

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
        }
    ) {
        self.controller = controller
        self.previewService = previewService
        self.refreshSwitcherContent = refreshSwitcherContent
        self.refreshStatusSurfaces = refreshStatusSurfaces
        self.scheduleDiscovery = scheduleDiscovery
        self.scheduleApply = scheduleApply
    }

    func handleOwnWindowVisibilityChanged() {
        handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))
    }

    func handle(_ events: WindowRuntimeEventBatch) {
        guard isObservationActive else {
            return
        }
        previewService.postponeBackgroundRefresh()
        pendingEvents.formUnion(events.events)
        processNextBatch()
    }

    func sessionActivityChanged(isActive: Bool) {
        guard isSessionActive != isActive else {
            return
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
            hasRetriedContinuityRecovery = false
        }
        isSystemAwake = isAwake
        hasPendingContinuityRecovery = hasPendingContinuityRecovery || isAwake
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
        let generation = sessionGeneration
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
        generation: UInt64
    ) {
        guard isObservationActive, generation == sessionGeneration else {
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
            hasPendingContinuityRecovery = result.continuityRecovery.isPending
            if !hasPendingContinuityRecovery {
                hasRetriedContinuityRecovery = false
            } else if !result.continuityRecovery.failedWindowIDs.isEmpty {
                retryContinuityRecoveryIfNeeded(for: events)
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
        let kind: WindowRuntimeEventKind = hasPendingContinuityRecovery
            ? .continuityRecovery
            : .sessionResumed
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

    func retryContinuityRecoveryIfNeeded(for events: WindowRuntimeEventBatch) {
        guard hasPendingContinuityRecovery,
              events.events.contains(where: { $0.kind == .continuityRecovery }),
              !hasRetriedContinuityRecovery
        else {
            return
        }
        hasRetriedContinuityRecovery = true
        appendContinuityRecovery()
    }

    func scheduleInitialContinuityVerificationIfNeeded(
        for events: WindowRuntimeEventBatch
    ) {
        guard hasPendingContinuityRecovery,
              events.events.contains(where: { $0.kind == .displayChanged })
        else {
            return
        }
        appendContinuityRecovery()
    }

    func handleDiscoveryFailure(
        _ error: Error,
        for events: WindowRuntimeEventBatch
    ) {
        retryContinuityRecoveryIfNeeded(for: events)
        log.error("Window update failed: \(String(describing: error))")
    }
}
