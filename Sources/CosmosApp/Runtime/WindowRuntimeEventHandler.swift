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
        pendingEvents.formUnion(events.events)
        processNextBatch()
    }

    private func processNextBatch() {
        guard !isProcessing, !pendingEvents.isEmpty else {
            return
        }

        let batch = WindowRuntimeEventBatch(events: pendingEvents)
        pendingEvents.removeAll()
        isProcessing = true
        scheduleDiscovery { [weak self] in
            guard let self else {
                return
            }
            let discovery = Result {
                try self.controller.discoverWindows(windowIDs: batch.discoveryWindowIDs)
            }
            scheduleApply { [weak self] in
                self?.apply(discovery, for: batch)
            }
        }
    }

    private func apply(
        _ discovery: Result<WindowDiscoverySnapshot, Error>,
        for events: WindowRuntimeEventBatch
    ) {
        defer {
            isProcessing = false
            processNextBatch()
        }

        do {
            let discovery = try discovery.get()
            let focusPolicy: ExternalWindowFocusPolicy = if events.containsApplicationActivation {
                .always
            } else if events.containsFocusChange || events.containsLayoutChange {
                .visibleFocusedWindow
            } else {
                .never
            }
            guard let result = try controller.applyExternalWindowChange(
                ExternalWindowChange(
                    displayConfigurationChanged: events.containsDisplayChange,
                    focusPolicy: focusPolicy
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
