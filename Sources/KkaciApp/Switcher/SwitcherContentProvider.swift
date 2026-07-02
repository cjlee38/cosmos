import Foundation
import KkaciCore

final class SwitcherContentProvider {
    private let controller: WorkspaceController
    private let previewProvider = WindowPreviewProvider()

    init(controller: WorkspaceController) {
        self.controller = controller
    }

    func windowItems(in workspace: String, from windows: [WindowSnapshot]) -> [WindowSwitcherItem] {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let orderedIDs = controller.windowIDsByMostRecentFocus(in: workspace)
        let orderedWindows = orderedIDs.compactMap { windowsByID[$0] }
        let orderedIDSet = Set(orderedIDs)
        let remainingWindows = windows
            .filter { controller.membership(for: $0.id) == workspace && !orderedIDSet.contains($0.id) }
            .sorted { $0.id < $1.id }

        return (orderedWindows + remainingWindows).map {
            previewProvider.makeItem(
                for: $0,
                includeThumbnail: !controller.isHiddenByWorkspace($0.id)
            )
        }
    }

    func workspaceGroups(from windows: [WindowSnapshot]) -> [WorkspaceSwitcherGroup] {
        controller.workspaces.map { workspace in
            WorkspaceSwitcherGroup(
                name: workspace,
                windows: windowItems(in: workspace, from: windows)
            )
        }
    }

    func overlayAnchorFrame(from windows: [WindowSnapshot]) -> WindowFrame? {
        if let focusedID = controller.focusedWindowID(),
           let focusedFrame = windows.first(where: { $0.id == focusedID })?.frame
        {
            return focusedFrame
        }

        return windows.first {
            controller.membership(for: $0.id) == controller.activeWorkspace
                && !controller.isHiddenByWorkspace($0.id)
                && !$0.isMinimized
                && $0.frame != nil
        }?.frame
    }

}
