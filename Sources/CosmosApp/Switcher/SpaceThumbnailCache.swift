import AppKit

final class SpaceThumbnailCache {
    private struct PendingRender {
        let group: SpaceThumbnailRenderGroup
        let generation: Int
    }

    private let render: (SpaceThumbnailRenderGroup) -> CGImage?
    private let renderQueue = DispatchQueue(label: "cosmos.space-thumbnails", qos: .userInitiated)
    private var thumbnails: [String: NSImage] = [:]
    private var pendingRenders: [String: PendingRender] = [:]
    private var pendingSpaceIDs: [String] = []
    private var generations: [String: Int] = [:]
    private var nextGeneration = 0
    private var liveSpaceIDs: Set<String> = []
    private var isRendering = false
    private var onThumbnailsUpdated: ((Set<String>) -> Void)?

    init(render: @escaping (SpaceThumbnailRenderGroup) -> CGImage? = SpaceThumbnailRenderer.render) {
        self.render = render
    }

    func thumbnail(for spaceID: String) -> NSImage? {
        thumbnails[spaceID]
    }

    func setUpdateHandler(_ handler: @escaping (Set<String>) -> Void) {
        onThumbnailsUpdated = handler
    }

    func removeStaleThumbnails(keeping spaceIDs: Set<String>) {
        liveSpaceIDs = spaceIDs
        thumbnails = thumbnails.filter { spaceIDs.contains($0.key) }
        pendingRenders = pendingRenders.filter { spaceIDs.contains($0.key) }
        pendingSpaceIDs.removeAll { !spaceIDs.contains($0) }
        generations = generations.filter { spaceIDs.contains($0.key) }
    }

    func invalidate() {
        thumbnails.removeAll()
        pendingRenders.removeAll()
        pendingSpaceIDs.removeAll()
        generations.removeAll()
    }

    func refresh(
        groups: [SpaceSwitcherGroup],
        prioritySpaceIDs: [String] = []
    ) {
        let renderGroups = SpaceThumbnailRenderer.makeRenderGroups(groups)
        let groupsByID = Dictionary(uniqueKeysWithValues: renderGroups.map { ($0.id, $0) })
        var seen: Set<String> = []
        let orderedIDs = (prioritySpaceIDs + renderGroups.map(\.id)).filter { id in
            groupsByID[id] != nil && seen.insert(id).inserted
        }
        let priorityIDs = Set(prioritySpaceIDs)
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
                pendingSpaceIDs.removeAll { $0 == id }
                pendingSpaceIDs.insert(id, at: priorityIndex)
                priorityIndex += 1
            } else if !pendingSpaceIDs.contains(id) {
                pendingSpaceIDs.append(id)
            }
        }
        startPendingRender()
    }

    private func startPendingRender() {
        guard !isRendering, let spaceID = pendingSpaceIDs.first else {
            return
        }
        pendingSpaceIDs.removeFirst()
        guard let pending = pendingRenders.removeValue(forKey: spaceID) else {
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
                if self.liveSpaceIDs.contains(spaceID),
                   self.generations[spaceID] == pending.generation {
                    self.thumbnails[spaceID] = image.map {
                        NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                    }
                    self.onThumbnailsUpdated?([spaceID])
                }
                self.startPendingRender()
            }
        }
    }
}
