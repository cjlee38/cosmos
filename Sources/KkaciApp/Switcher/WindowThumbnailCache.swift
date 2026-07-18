import AppKit
import CoreGraphics
import KkaciCore

final class WindowThumbnailCache {
    private let captureImage: (WindowID) -> CGImage?
    private let captureQueue = DispatchQueue(label: "kkaci.window-thumbnails", qos: .userInitiated)
    private var thumbnails: [WindowID: NSImage] = [:]
    private var queuedWindowIDs: [WindowID] = []
    private var capturingWindowIDs: Set<WindowID> = []
    private var liveWindowIDs: Set<WindowID> = []
    private var onThumbnailUpdated: ((WindowID) -> Void)?

    init(captureImage: @escaping (WindowID) -> CGImage? = WindowThumbnailCapture.capture) {
        self.captureImage = captureImage
    }

    func setUpdateHandler(_ handler: @escaping (WindowID) -> Void) {
        onThumbnailUpdated = handler
    }

    func thumbnail(for id: WindowID) -> NSImage? {
        thumbnails[id]
    }

    func removeStaleThumbnails(keeping liveIDs: Set<WindowID>) {
        liveWindowIDs = liveIDs
        thumbnails = thumbnails.filter { liveIDs.contains($0.key) }
        queuedWindowIDs.removeAll { !liveIDs.contains($0) }
    }

    func refresh(windowIDs: [WindowID]) {
        for windowID in windowIDs
            where liveWindowIDs.contains(windowID) && !queuedWindowIDs.contains(windowID) {
            queuedWindowIDs.append(windowID)
        }
        startNextCaptureBatch()
    }

    private func startNextCaptureBatch() {
        guard capturingWindowIDs.isEmpty, !queuedWindowIDs.isEmpty else {
            return
        }

        let windowIDs = queuedWindowIDs
        queuedWindowIDs.removeAll()
        capturingWindowIDs = Set(windowIDs)

        captureQueue.async { [weak self, captureImage] in
            for windowID in windowIDs {
                let image = captureImage(windowID)
                DispatchQueue.main.async { [weak self] in
                    self?.completeCapture(windowID: windowID, image: image)
                }
            }
        }
    }

    private func completeCapture(windowID: WindowID, image: CGImage?) {
        capturingWindowIDs.remove(windowID)
        if liveWindowIDs.contains(windowID) {
            if let image {
                thumbnails[windowID] = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            } else {
                thumbnails[windowID] = nil
            }
            onThumbnailUpdated?(windowID)
        }

        guard capturingWindowIDs.isEmpty else {
            return
        }
        if !queuedWindowIDs.isEmpty {
            startNextCaptureBatch()
        }
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
