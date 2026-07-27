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
    private var isProcessing = false
    private var isSessionActive = true
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
        guard isSessionActive else {
            return
        }
        pendingEvents.formUnion(events.events)
        processNextBatch()
    }

    func sessionActivityChanged(isActive: Bool) {
        guard isSessionActive != isActive else {
            return
        }

        isSessionActive = isActive
        sessionGeneration &+= 1
        pendingEvents.removeAll()
        if isActive {
            handle(WindowRuntimeEventBatch(events: [
                WindowRuntimeEvent(kind: .sessionResumed, windowID: nil)
            ]))
        }
    }

    private func processNextBatch() {
        guard isSessionActive, !isProcessing, !pendingEvents.isEmpty else {
            return
        }

        let batch = WindowRuntimeEventBatch(events: pendingEvents)
        let generation = sessionGeneration
        pendingEvents.removeAll()
        isProcessing = true
        scheduleDiscovery { [weak self] in
            guard let self else {
                return
            }
            let discovery = Result {
                try self.controller.discoverWindows(
                    windowIDs: batch.discoveryWindowIDs,
                    mode: batch.isSessionResumeRecovery ? .sessionRecovery : .normal
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
        guard isSessionActive, generation == sessionGeneration else {
            isProcessing = false
            processNextBatch()
            return
        }

        defer {
            isProcessing = false
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
                    destroyedWindowIDs: events.destroyedWindowIDs
                ),
                discovery: discovery
            ) else {
                pendingEvents.formUnion(events.events)
                return
            }
            refreshPreviews(for: events, result: result)
            refreshSwitcherContent()
            refreshStatusSurfaces()
            if case let .switched(windowID, space) = result.focusedWindowSync {
                log.info("Switched to space \(space) for \(windowID)")
            }
        } catch {
            log.error("Window update failed: \(String(describing: error))")
        }
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
        previewService.refresh(
            windowIDs: windowIDs,
            spaceIDs: spaceIDs,
            priorityIDs: focusedWindowID.map { [$0] } ?? []
        )
    }
}
