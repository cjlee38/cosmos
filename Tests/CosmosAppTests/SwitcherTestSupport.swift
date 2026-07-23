import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import Foundation
import XCTest

enum SwitcherTestWindowSystemError: Error {
    case frameWrite(WindowID)
    case windowNotFound(WindowID)
}

final class SwitcherTestWindowSystem: WindowSystem {
    var windows: [WindowSnapshot]
    var focusedWindowIDValue: WindowID?
    var frameWriteFailures: Set<WindowID> = []
    var discoveryApplyResults: [Bool] = []
    var unresolvedWindowIDs: Set<WindowID> = []
    private(set) var refreshCount = 0
    private(set) var discoveryRequests: [Set<WindowID>?] = []
    private(set) var discoveryModes: [WindowDiscoveryMode] = []
    private(set) var focusedWindowIDs: [WindowID] = []
    private var framesByID: [WindowID: WindowFrame]

    init(windows: [WindowSnapshot]) {
        self.windows = windows
        framesByID = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.frame.map { (window.id, $0) }
        })
    }

    func replaceWindows(_ windows: [WindowSnapshot]) {
        self.windows = windows
        framesByID = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.frame.map { (window.id, $0) }
        })
    }

    func resetDiscoveryRequests() {
        discoveryRequests.removeAll()
    }

    func resetDiscoveryModes() {
        discoveryModes.removeAll()
    }

    func refresh() throws -> [WindowSnapshot] {
        refreshCount += 1
        return windows.map { window in
            WindowSnapshot(
                id: window.id,
                app: window.app,
                title: window.title,
                frame: framesByID[window.id] ?? window.frame,
                isMinimized: window.isMinimized
            )
        }
    }

    func discover(
        windowIDs: Set<WindowID>?,
        mode: WindowDiscoveryMode
    ) throws -> WindowDiscoverySnapshot {
        discoveryRequests.append(windowIDs)
        discoveryModes.append(mode)
        let windows = try refresh()
        return WindowDiscoverySnapshot(
            scope: windowIDs.map(WindowDiscoverySnapshot.Scope.windows) ?? .full,
            windows: windowIDs.map { ids in windows.filter { ids.contains($0.id) } } ?? windows,
            focusedWindowID: focusedWindowIDValue,
            frontToBackWindowIDs: windows.map(\.id),
            unresolvedWindowIDs: unresolvedWindowIDs
        )
    }

    func apply(_: WindowDiscoverySnapshot) -> Bool {
        discoveryApplyResults.isEmpty ? true : discoveryApplyResults.removeFirst()
    }

    func contains(_ id: WindowID) -> Bool {
        windows.contains { $0.id == id }
    }

    func focusedWindowID() -> WindowID? {
        focusedWindowIDValue
    }

    func frame(for id: WindowID) -> WindowFrame? {
        framesByID[id]
    }

    func setPosition(_ point: CGPoint, for id: WindowID) throws {
        guard contains(id) else {
            throw SwitcherTestWindowSystemError.windowNotFound(id)
        }
        if frameWriteFailures.contains(id) {
            throw SwitcherTestWindowSystemError.frameWrite(id)
        }
        guard var frame = framesByID[id] else {
            return
        }
        frame.origin = point
        framesByID[id] = frame
    }

    func setFrame(_ frame: WindowFrame, for id: WindowID) throws {
        guard contains(id) else {
            throw SwitcherTestWindowSystemError.windowNotFound(id)
        }
        if frameWriteFailures.contains(id) {
            throw SwitcherTestWindowSystemError.frameWrite(id)
        }
        framesByID[id] = frame
    }

    func focus(_ id: WindowID) {
        guard contains(id) else {
            return
        }
        focusedWindowIDValue = id
        focusedWindowIDs.append(id)
    }
}

struct SwitcherTestDisplayProvider: DisplayProviding {
    let snapshots: [DisplaySnapshot]

    init(snapshots: [DisplaySnapshot] = [DisplaySnapshot(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
        role: .main
    )]) {
        self.snapshots = snapshots
    }

    func displays() throws -> [DisplaySnapshot] {
        snapshots
    }
}

func makeSwitcherTestWindow(
    id: WindowID,
    title: String,
    pid: pid_t = 1,
    frame: WindowFrame? = nil
) -> WindowSnapshot {
    WindowSnapshot(
        id: id,
        app: RunningAppInfo(pid: pid, name: "App \(pid)"),
        title: title,
        frame: frame ?? WindowFrame(
            origin: CGPoint(x: CGFloat(id), y: CGFloat(id)),
            size: CGSize(width: 200, height: 120)
        ),
        isMinimized: false
    )
}

func makeSwitcherTestController(
    windows: [WindowSnapshot],
    displays: [DisplaySnapshot]? = nil
) throws -> (SpaceController, SwitcherTestWindowSystem) {
    let windowSystem = SwitcherTestWindowSystem(windows: windows)
    let controller = SpaceController(
        windowSystem: windowSystem,
        displayProvider: displays.map { SwitcherTestDisplayProvider(snapshots: $0) }
            ?? SwitcherTestDisplayProvider()
    )
    try controller.bootstrapWindowState()
    return (controller, windowSystem)
}

@discardableResult
func moveSwitcherTestWindow(
    _ id: WindowID,
    to space: String,
    controller: SpaceController,
    windowSystem: SwitcherTestWindowSystem
) throws -> WindowMoveResult? {
    let originalSpace = controller.currentSpace
    if controller.membership(for: id) == space {
        return nil
    }
    if let sourceSpace = controller.membership(for: id),
       sourceSpace != controller.currentSpace {
        _ = try controller.switchSpace(to: sourceSpace)
    }
    windowSystem.focusedWindowIDValue = id
    _ = try controller.handleFocusedWindowChanged()
    let result = try controller.moveFocusedWindow(to: space)
    if controller.currentSpace != originalSpace {
        _ = try controller.switchSpace(to: originalSpace)
    }
    return result
}

func makeSwitcherTestPreviewService(
    controller: SpaceController,
    captureImage: @escaping (WindowID) -> CGImage? = { _ in nil },
    canCapture: @escaping () -> Bool = { true },
    renderSpace: @escaping (SpaceThumbnailRenderGroup) -> CGImage? = SpaceThumbnailRenderer.render,
    loadIcon: @escaping (pid_t) -> NSImage? = { _ in nil }
) -> SwitcherPreviewService {
    SwitcherPreviewService(
        controller: controller,
        windowThumbnailCache: WindowThumbnailCache(captureImage: captureImage, canCapture: canCapture),
        spaceThumbnailCache: SpaceThumbnailCache(render: renderSpace),
        applicationIconCache: ApplicationIconCache(loadIcon: loadIcon)
    )
}

func makeSwitcherTestImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    return context.makeImage()!
}

final class SwitcherOverlaySpy: SwitcherOverlayPresenting {
    var isOverlayVisible = false
    var shownWindowIDs: [[WindowID]] = []
    var shownWindowSelections: [WindowID] = []
    var reboundWindowIDs: [[WindowID]] = []
    var reboundWindowSelections: [WindowID] = []
    var updatedWindowIDs: [[WindowID]] = []
    var shownSpaceIDs: [[String]] = []
    var reboundSpaceIDs: [[String]] = []
    var onWindowShown: (() -> Void)?
    var onWindowPreviewsUpdated: (() -> Void)?
    var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onSpaceKey: ((String) -> Bool)?

    func setInteractionHandlers(
        onArrowKey: @escaping (SwitcherArrowDirection) -> Void,
        onOutsideClick: @escaping () -> Void,
        onSpaceKey: @escaping (String) -> Bool
    ) {
        self.onArrowKey = onArrowKey
        self.onOutsideClick = onOutsideClick
        self.onSpaceKey = onSpaceKey
    }

    func showWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (WindowID) -> Void,
        onClick _: @escaping (WindowID) -> Void
    ) {
        shownWindowIDs.append(items.map(\.windowID))
        shownWindowSelections.append(selectedID)
        isOverlayVisible = true
        onWindowShown?()
    }

    func rebindWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (WindowID) -> Void,
        onClick _: @escaping (WindowID) -> Void
    ) {
        reboundWindowIDs.append(items.map(\.windowID))
        reboundWindowSelections.append(selectedID)
    }

    func showSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID _: String,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (String) -> Void,
        onClick _: @escaping (String) -> Void
    ) {
        shownSpaceIDs.append(groups.map(\.id))
        isOverlayVisible = true
    }

    func rebindSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID _: String,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (String) -> Void,
        onClick _: @escaping (String) -> Void
    ) {
        reboundSpaceIDs.append(groups.map(\.id))
    }

    func updateWindowSwitcher(items: [WindowSwitcherItem]) {
        updatedWindowIDs.append(items.map(\.windowID))
        onWindowPreviewsUpdated?()
    }

    func updateWindowSelection(selectedID _: WindowID) {}

    func updateSpaceSwitcher(groups _: [SpaceSwitcherGroup]) {}

    func updateSpaceSelection(selectedID _: String) {}

    func hideOverlay() {
        isOverlayVisible = false
    }
}
