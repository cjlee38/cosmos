import AppKit
import CoreGraphics
import CosmosCore
import ScreenCaptureKit

final class WindowThumbnailCache {
    typealias CaptureImages = (
        [WindowID],
        @escaping (WindowID, Result<CGImage?, Error>) -> Void
    ) -> Void

    private let captureImages: CaptureImages
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

    convenience init(
        canCapture: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        maximumAge: TimeInterval = 2,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.init(
            captureImages: WindowThumbnailCapture.capture,
            canCapture: canCapture,
            maximumAge: maximumAge,
            currentTime: currentTime
        )
    }

    convenience init(
        captureImage: @escaping (WindowID) -> CGImage?,
        canCapture: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        maximumAge: TimeInterval = 2,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.init(
            captureImages: { windowIDs, completion in
                for windowID in windowIDs {
                    completion(windowID, .success(captureImage(windowID)))
                }
            },
            canCapture: canCapture,
            maximumAge: maximumAge,
            currentTime: currentTime
        )
    }

    init(
        captureImages: @escaping CaptureImages,
        canCapture: @escaping () -> Bool,
        maximumAge: TimeInterval,
        currentTime: @escaping () -> TimeInterval
    ) {
        self.captureImages = captureImages
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

        captureQueue.async { [weak self, captureImages] in
            captureImages(windowIDs) { windowID, result in
                DispatchQueue.main.async { [weak self] in
                    self?.completeCapture(windowID: windowID, result: result)
                }
            }
        }
    }

    private func completeCapture(windowID: WindowID, result: Result<CGImage?, Error>) {
        capturingWindowIDs.remove(windowID)
        if liveWindowIDs.contains(windowID), isCaptureAvailable {
            switch result {
            case let .success(image):
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
            case .failure:
                dirtyWindowIDs.insert(windowID)
            }
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
    static func capture(
        windowIDs: [WindowID],
        completion: @escaping (WindowID, Result<CGImage?, Error>) -> Void
    ) {
        SCShareableContent.getExcludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        ) { content, error in
            guard let content else {
                let error = error ?? WindowThumbnailCaptureError.contentUnavailable
                windowIDs.forEach { completion($0, .failure(error)) }
                return
            }

            let windowsByID = Dictionary(
                uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) }
            )

            func capture(at index: Int) {
                guard index < windowIDs.count else {
                    return
                }

                let windowID = windowIDs[index]
                guard let window = windowsByID[windowID] else {
                    completion(windowID, .success(nil))
                    capture(at: index + 1)
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
                configuration.width = max(1, Int(window.frame.width * scale))
                configuration.height = max(1, Int(window.frame.height * scale))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true

                SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) { image, error in
                    if let error {
                        completion(windowID, .failure(error))
                    } else {
                        completion(windowID, .success(image))
                    }
                    capture(at: index + 1)
                }
            }

            capture(at: 0)
        }
    }
}

private enum WindowThumbnailCaptureError: Error {
    case contentUnavailable
}
