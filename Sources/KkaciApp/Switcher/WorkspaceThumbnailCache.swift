import AppKit

final class WorkspaceThumbnailCache {
    private struct PendingRender {
        let group: WorkspaceThumbnailRenderGroup
        let generation: Int
    }

    private let render: (WorkspaceThumbnailRenderGroup) -> CGImage?
    private let renderQueue = DispatchQueue(label: "kkaci.workspace-thumbnails", qos: .userInitiated)
    private var thumbnails: [String: NSImage] = [:]
    private var pendingRenders: [String: PendingRender] = [:]
    private var pendingWorkspaceIDs: [String] = []
    private var generations: [String: Int] = [:]
    private var nextGeneration = 0
    private var liveWorkspaceIDs: Set<String> = []
    private var isRendering = false
    private var onThumbnailsUpdated: ((Set<String>) -> Void)?

    init(render: @escaping (WorkspaceThumbnailRenderGroup) -> CGImage? = WorkspaceThumbnailRenderer.render) {
        self.render = render
    }

    func thumbnail(for workspaceID: String) -> NSImage? {
        thumbnails[workspaceID]
    }

    func setUpdateHandler(_ handler: @escaping (Set<String>) -> Void) {
        onThumbnailsUpdated = handler
    }

    func removeStaleThumbnails(keeping workspaceIDs: Set<String>) {
        liveWorkspaceIDs = workspaceIDs
        thumbnails = thumbnails.filter { workspaceIDs.contains($0.key) }
        pendingRenders = pendingRenders.filter { workspaceIDs.contains($0.key) }
        pendingWorkspaceIDs.removeAll { !workspaceIDs.contains($0) }
        generations = generations.filter { workspaceIDs.contains($0.key) }
    }

    func invalidate() {
        thumbnails.removeAll()
        pendingRenders.removeAll()
        pendingWorkspaceIDs.removeAll()
        generations.removeAll()
    }

    func refresh(
        groups: [WorkspaceSwitcherGroup],
        priorityWorkspaceIDs: [String] = []
    ) {
        let renderGroups = WorkspaceThumbnailRenderer.makeRenderGroups(groups)
        let groupsByID = Dictionary(uniqueKeysWithValues: renderGroups.map { ($0.id, $0) })
        var seen: Set<String> = []
        let orderedIDs = (priorityWorkspaceIDs + renderGroups.map(\.id)).filter { id in
            groupsByID[id] != nil && seen.insert(id).inserted
        }
        let priorityIDs = Set(priorityWorkspaceIDs)
        var priorityIndex = 0

        for id in orderedIDs {
            guard let group = groupsByID[id] else {
                continue
            }
            nextGeneration += 1
            let generation = nextGeneration
            generations[id] = generation
            pendingRenders[id] = PendingRender(group: group, generation: generation)
            if priorityIDs.contains(id) {
                pendingWorkspaceIDs.removeAll { $0 == id }
                pendingWorkspaceIDs.insert(id, at: priorityIndex)
                priorityIndex += 1
            } else if !pendingWorkspaceIDs.contains(id) {
                pendingWorkspaceIDs.append(id)
            }
        }
        startPendingRender()
    }

    private func startPendingRender() {
        guard !isRendering, let workspaceID = pendingWorkspaceIDs.first else {
            return
        }
        pendingWorkspaceIDs.removeFirst()
        guard let pending = pendingRenders.removeValue(forKey: workspaceID) else {
            startPendingRender()
            return
        }
        isRendering = true
        renderQueue.async { [weak self, render] in
            let image = render(pending.group)
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isRendering = false
                if self.liveWorkspaceIDs.contains(workspaceID),
                   self.generations[workspaceID] == pending.generation {
                    self.thumbnails[workspaceID] = image.map {
                        NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                    }
                    self.onThumbnailsUpdated?([workspaceID])
                }
                self.startPendingRender()
            }
        }
    }
}
