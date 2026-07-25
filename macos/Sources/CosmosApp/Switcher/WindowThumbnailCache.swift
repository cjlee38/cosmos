import AppKit
import CoreGraphics
import CosmosCore

final class WindowThumbnailCache {
    private let captureImage: (WindowID) -> CGImage?
    private let canCapture: () -> Bool
    private let maximumAge: TimeInterval
    private let currentTime: () -> TimeInterval
    private let captureQueue = DispatchQueue(label: "cosmos.window-thumbnails", qos: .userInitiated)
    private var thumbnails: [WindowID: NSImage] = [:]
    private var lastCaptureTimes: [WindowID: TimeInterval] = [:]
    private var queuedWindowIDs: [WindowID] = []
    private var capturingWindowIDs: Set<WindowID> = []
    private var dirtyWindowIDs: Set<WindowID> = []
    private var liveWindowIDs: Set<WindowID> = []
    private var onThumbnailUpdated: ((WindowID) -> Void)?

    private(set) var isCaptureAvailable: Bool

    init(
        captureImage: @escaping (WindowID) -> CGImage? = WindowThumbnailCapture.capture,
        canCapture: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        maximumAge: TimeInterval = 2,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.captureImage = captureImage
        self.canCapture = canCapture
        self.maximumAge = maximumAge
        self.currentTime = currentTime
        isCaptureAvailable = canCapture()
    }

    func setUpdateHandler(_ handler: @escaping (WindowID) -> Void) {
        onThumbnailUpdated = handler
    }

    func thumbnail(for id: WindowID) -> NSImage? {
        isCaptureAvailable ? thumbnails[id] : nil
    }

    func removeStaleThumbnails(keeping liveIDs: Set<WindowID>) {
        liveWindowIDs = liveIDs
        thumbnails = thumbnails.filter { liveIDs.contains($0.key) }
        lastCaptureTimes = lastCaptureTimes.filter { liveIDs.contains($0.key) }
        queuedWindowIDs.removeAll { !liveIDs.contains($0) }
        dirtyWindowIDs.formIntersection(liveIDs)
    }

    func markDirty(_ windowIDs: Set<WindowID>) {
        dirtyWindowIDs.formUnion(windowIDs.intersection(liveWindowIDs))
    }

    func refresh(windowIDs: [WindowID]) {
        guard refreshCaptureAvailability() else {
            return
        }
        let now = currentTime()
        for windowID in windowIDs where shouldQueueCapture(windowID, at: now) {
            queuedWindowIDs.append(windowID)
        }
        startNextCaptureBatch()
    }

    @discardableResult
    func refreshCaptureAvailability() -> Bool {
        isCaptureAvailable = canCapture()
        if !isCaptureAvailable {
            thumbnails.removeAll()
            lastCaptureTimes.removeAll()
            queuedWindowIDs.removeAll()
            dirtyWindowIDs.removeAll()
        }
        return isCaptureAvailable
    }

    private func shouldQueueCapture(_ windowID: WindowID, at now: TimeInterval) -> Bool {
        guard liveWindowIDs.contains(windowID),
              !queuedWindowIDs.contains(windowID)
        else {
            return false
        }

        let isDirty = dirtyWindowIDs.contains(windowID)
        if capturingWindowIDs.contains(windowID), !isDirty {
            return false
        }
        let isExpired = lastCaptureTimes[windowID].map { now - $0 >= maximumAge } ?? true
        return isDirty || isExpired
    }

    private func startNextCaptureBatch() {
        guard capturingWindowIDs.isEmpty, !queuedWindowIDs.isEmpty else {
            return
        }

        let windowIDs = queuedWindowIDs
        queuedWindowIDs.removeAll()
        capturingWindowIDs = Set(windowIDs)
        dirtyWindowIDs.subtract(windowIDs)

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
        if liveWindowIDs.contains(windowID), isCaptureAvailable {
            lastCaptureTimes[windowID] = currentTime()
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
