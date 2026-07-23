import AppKit
import CosmosCore

struct SwitcherPreviewUpdate {
    let windowIDs: Set<WindowID>
    let spaceIDs: Set<String>
}

final class SwitcherPreviewService {
    private let controller: SpaceController
    private let windowThumbnailCache: WindowThumbnailCache
    private let spaceThumbnailCache: SpaceThumbnailCache
    private let applicationIconCache: ApplicationIconCache
    private var pendingUpdatedWindowIDs: Set<WindowID> = []
    private var pendingUpdatedSpaceIDs: Set<String> = []
    private var isUpdateNotificationScheduled = false
    private var onUpdate: ((SwitcherPreviewUpdate) -> Void)?

    init(
        controller: SpaceController,
        windowThumbnailCache: WindowThumbnailCache,
        spaceThumbnailCache: SpaceThumbnailCache,
        applicationIconCache: ApplicationIconCache
    ) {
        self.controller = controller
        self.windowThumbnailCache = windowThumbnailCache
        self.spaceThumbnailCache = spaceThumbnailCache
        self.applicationIconCache = applicationIconCache

        windowThumbnailCache.setUpdateHandler { [weak self] windowID in
            self?.handleWindowThumbnailUpdated(windowID)
        }
        spaceThumbnailCache.setUpdateHandler { [weak self] spaceIDs in
            self?.notify(spaceIDs: spaceIDs)
        }
        applicationIconCache.setUpdateHandler { [weak self] pid in
            self?.handleApplicationIconUpdated(pid)
        }
    }

    func setUpdateHandler(_ handler: @escaping (SwitcherPreviewUpdate) -> Void) {
        onUpdate = handler
    }

    func windowItems(ids: [WindowID]) -> [WindowSwitcherItem] {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: controller.currentWindows().map { ($0.id, $0) }
        )
        return ids.compactMap { id in
            windowsByID[id].map(makeItem)
        }
    }

    func spaceGroups(ids: [String]) -> [SpaceSwitcherGroup] {
        let previewStyle = currentSpacePreviewStyle()
        if previewStyle == .applicationIcons {
            spaceThumbnailCache.invalidate()
        }
        return makeSpaceGroups(ids: ids, previewStyle: previewStyle)
    }

    private func makeSpaceGroups(
        ids: [String],
        previewStyle: SpacePreviewStyle
    ) -> [SpaceSwitcherGroup] {
        let liveSpaceIDs = Set(controller.spaces)
        let shortcuts = SpaceShortcutBindings(controller.currentConfig.configuredShortcuts)
        return ids.compactMap { spaceID in
            guard liveSpaceIDs.contains(spaceID),
                  let displayFrame = displayFrame(for: spaceID)
            else {
                return nil
            }
            return SpaceSwitcherGroup(
                id: spaceID,
                displayFrame: displayFrame,
                windows: controller.windows(in: spaceID).map(makeItem),
                preview: previewStyle == .spatial
                    ? spaceThumbnailCache.thumbnail(for: spaceID)
                    : nil,
                previewStyle: previewStyle,
                shortcutKey: shortcuts.key(for: spaceID)
            )
        }
    }

    func refresh(
        windowIDs: Set<WindowID>,
        spaceIDs: Set<String>,
        priorityIDs: [WindowID] = []
    ) {
        let windows = controller.currentWindows()
        let liveWindowIDs = Set(windows.map(\.id))
        let liveSpaceIDs = Set(controller.spaces)

        windowThumbnailCache.removeStaleThumbnails(keeping: liveWindowIDs)
        spaceThumbnailCache.removeStaleThumbnails(keeping: liveSpaceIDs)
        refreshApplicationIcons(windows: windows)
        let requestedSpaceIDs = spaceIDs.intersection(liveSpaceIDs)
        let prioritySpaceIDs = priorityIDs.compactMap(controller.membership(for:))
        refreshSpaces(ids: requestedSpaceIDs, priorityIDs: prioritySpaceIDs)
        windowThumbnailCache.refresh(windowIDs: orderedWindowIDs(
            windowIDs.intersection(liveWindowIDs),
            windows: windows,
            priorityIDs: priorityIDs
        ))
    }

    func markWindowThumbnailsDirty(_ windowIDs: Set<WindowID>) {
        windowThumbnailCache.markDirty(windowIDs)
    }

    func refreshSpaces(ids: Set<String>, priorityIDs: [String] = []) {
        let liveSpaceIDs = Set(controller.spaces)
        let ids = ids.intersection(liveSpaceIDs)
        spaceThumbnailCache.removeStaleThumbnails(keeping: liveSpaceIDs)
        let previewStyle = currentSpacePreviewStyle()
        guard previewStyle == .spatial else {
            spaceThumbnailCache.invalidate()
            notify(spaceIDs: ids)
            return
        }
        spaceThumbnailCache.refresh(
            groups: makeSpaceGroups(
                ids: controller.spaces.filter(ids.contains),
                previewStyle: previewStyle
            ),
            prioritySpaceIDs: priorityIDs
        )
    }

    func refreshAll(priorityIDs: [WindowID] = []) {
        let windows = controller.currentWindows()
        refresh(
            windowIDs: Set(windows.map(\.id)),
            spaceIDs: Set(controller.spaces),
            priorityIDs: priorityIDs
        )
    }

    private func orderedWindowIDs(
        _ requestedWindowIDs: Set<WindowID>,
        windows: [WindowSnapshot],
        priorityIDs: [WindowID]
    ) -> [WindowID] {
        var seen: Set<WindowID> = []
        return (priorityIDs + windows.map(\.id)).filter { windowID in
            requestedWindowIDs.contains(windowID) && seen.insert(windowID).inserted
        }
    }

    private func makeItem(for window: WindowSnapshot) -> WindowSwitcherItem {
        WindowSwitcherItem(
            windowID: window.id,
            appName: window.app.name,
            title: window.title,
            frame: controller.spaceFrame(for: window.id),
            preview: windowThumbnailCache.thumbnail(for: window.id),
            icon: applicationIconCache.icon(for: window.app.pid)
        )
    }

    private func displayFrame(for spaceID: String) -> CGRect? {
        let monitorSlot = controller.effectiveMonitorSlot(for: spaceID)
        return controller.displayTopology.monitorSlots
            .first { $0.slot == monitorSlot }?
            .display.frame
    }

    private func refreshApplicationIcons(windows: [WindowSnapshot]) {
        applicationIconCache.refresh(pids: Set(windows.map(\.app.pid)))
    }

    private func currentSpacePreviewStyle() -> SpacePreviewStyle {
        windowThumbnailCache.refreshCaptureAvailability() ? .spatial : .applicationIcons
    }

    private func handleApplicationIconUpdated(_ pid: pid_t) {
        let windowIDs = Set(controller.currentWindows().filter { $0.app.pid == pid }.map(\.id))
        guard !windowIDs.isEmpty else {
            return
        }

        notify(windowIDs: windowIDs)
        refreshSpaces(ids: Set(windowIDs.compactMap(controller.membership(for:))))
    }

    private func handleWindowThumbnailUpdated(_ windowID: WindowID) {
        notify(windowIDs: [windowID])
        guard let spaceID = controller.membership(for: windowID) else {
            return
        }
        refreshSpaces(ids: [spaceID], priorityIDs: [spaceID])
    }

    private func notify(
        windowIDs: Set<WindowID> = [],
        spaceIDs: Set<String> = []
    ) {
        pendingUpdatedWindowIDs.formUnion(windowIDs)
        pendingUpdatedSpaceIDs.formUnion(spaceIDs)
        guard !isUpdateNotificationScheduled else {
            return
        }

        isUpdateNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let update = SwitcherPreviewUpdate(
                windowIDs: pendingUpdatedWindowIDs,
                spaceIDs: pendingUpdatedSpaceIDs
            )
            pendingUpdatedWindowIDs.removeAll()
            pendingUpdatedSpaceIDs.removeAll()
            isUpdateNotificationScheduled = false
            onUpdate?(update)
        }
    }
}
