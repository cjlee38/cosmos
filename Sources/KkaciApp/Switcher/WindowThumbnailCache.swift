import AppKit
import CoreGraphics
import KkaciCore

final class WindowThumbnailCache {
    private let captureImage: (WindowID) -> CGImage?
    private let captureQueue = DispatchQueue(label: "kkaci.window-thumbnails", qos: .userInitiated)
    private var thumbnails: [WindowID: NSImage] = [:]
    private var inFlight: Set<WindowID> = []

    init(captureImage: @escaping (WindowID) -> CGImage? = WindowThumbnailCapture.capture) {
        self.captureImage = captureImage
    }

    func thumbnail(for id: WindowID) -> NSImage? {
        thumbnails[id]
    }

    func removeStaleThumbnails(keeping liveIDs: Set<WindowID>) {
        thumbnails = thumbnails.filter { liveIDs.contains($0.key) }
        inFlight = inFlight.intersection(liveIDs)
    }

    func refresh(
        windows: [WindowSnapshot],
        priorityIDs: [WindowID] = [],
        onThumbnailUpdated: @escaping (WindowID) -> Void = { _ in }
    ) {
        let ids = orderedWindowIDs(windows: windows, priorityIDs: priorityIDs)
        let pendingIDs = ids.filter { inFlight.insert($0).inserted }

        for id in pendingIDs {
            captureQueue.async { [captureImage] in
                let image = captureImage(id)
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }

                    inFlight.remove(id)
                    guard let image else {
                        return
                    }

                    thumbnails[id] = NSImage(
                        cgImage: image,
                        size: NSSize(width: image.width, height: image.height)
                    )
                    onThumbnailUpdated(id)
                }
            }
        }
    }

    private func orderedWindowIDs(windows: [WindowSnapshot], priorityIDs: [WindowID]) -> [WindowID] {
        var seen = Set<WindowID>()
        var ids: [WindowID] = []

        for id in priorityIDs where seen.insert(id).inserted {
            ids.append(id)
        }

        for window in windows where seen.insert(window.id).inserted {
            ids.append(window.id)
        }

        return ids
    }
}

private enum WindowThumbnailCapture {
    static func capture(id: WindowID) -> CGImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return image
    }
}
