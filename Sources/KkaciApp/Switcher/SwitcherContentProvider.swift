import Foundation
import KkaciCore

final class SwitcherContentProvider {
    private let controller: WorkspaceController
    private let previewProvider: WindowPreviewProvider
    private let workspaceThumbnailCache: WorkspaceThumbnailCache

    init(
        controller: WorkspaceController,
        windowThumbnailCache: WindowThumbnailCache,
        workspaceThumbnailCache: WorkspaceThumbnailCache,
        applicationIconCache: ApplicationIconCache
    ) {
        self.controller = controller
        previewProvider = WindowPreviewProvider(
            thumbnailCache: windowThumbnailCache,
            applicationIconCache: applicationIconCache
        )
        self.workspaceThumbnailCache = workspaceThumbnailCache
    }

    func windowItems(withIDs ids: [WindowID], from windows: [WindowSnapshot]) -> [WindowSwitcherItem] {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return ids.compactMap { id in
            windowsByID[id].map { window in
                previewProvider.makeItem(
                    for: window,
                    frame: controller.workspaceFrame(for: id)
                )
            }
        }
    }

    func workspaceGroups() -> [WorkspaceSwitcherGroup] {
        controller.workspaces.map { workspace in
            WorkspaceSwitcherGroup(
                name: workspace,
                windows: workspacePreviewItems(in: workspace),
                preview: workspaceThumbnailCache.thumbnail(for: workspace)
            )
        }
    }

    func overlayAnchorFrame(from windows: [WindowSnapshot], preferredWindowID: WindowID?) -> WindowFrame? {
        if let preferredWindowID,
           let preferredFrame = windows.first(where: { $0.id == preferredWindowID })?.frame {
            return preferredFrame
        }

        return windows.first {
            controller.membership(for: $0.id) == controller.activeWorkspace
                && !controller.isHiddenByWorkspace($0.id)
                && !$0.isMinimized
                && $0.frame != nil
        }?.frame
    }

    private func workspacePreviewItems(in workspace: String) -> [WindowSwitcherItem] {
        controller.windows(in: workspace)
            .map { window in
                previewProvider.makeItem(
                    for: window,
                    frame: controller.workspaceFrame(for: window.id)
                )
            }
    }
}
