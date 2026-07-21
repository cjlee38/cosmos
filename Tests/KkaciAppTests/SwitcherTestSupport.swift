import AppKit
import CoreGraphics
import Foundation
@testable import KkaciApp
import KkaciCore
import XCTest

enum SwitcherTestWindowSystemError: Error {
    case frameWrite(WindowID)
    case windowNotFound(WindowID)
}

final class SwitcherTestWindowSystem: WindowSystem {
    var windows: [WindowSnapshot]
    var focusedWindowIDValue: WindowID?
    var frameWriteFailures: Set<WindowID> = []
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

    func refresh() throws -> [WindowSnapshot] {
        windows.map { window in
            WindowSnapshot(
                id: window.id,
                app: window.app,
                title: window.title,
                frame: framesByID[window.id] ?? window.frame,
                isMinimized: window.isMinimized
            )
        }
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
) throws -> (WorkspaceController, SwitcherTestWindowSystem) {
    let windowSystem = SwitcherTestWindowSystem(windows: windows)
    let controller = WorkspaceController(
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
    to workspace: String,
    controller: WorkspaceController,
    windowSystem: SwitcherTestWindowSystem
) throws -> WindowMoveResult? {
    let originalWorkspace = controller.currentWorkspace
    if controller.membership(for: id) == workspace {
        return nil
    }
    if let sourceWorkspace = controller.membership(for: id),
       sourceWorkspace != controller.currentWorkspace {
        _ = try controller.switchWorkspace(to: sourceWorkspace)
    }
    windowSystem.focusedWindowIDValue = id
    _ = try controller.handleFocusedWindowChanged()
    let result = try controller.moveFocusedWindow(to: workspace)
    if controller.currentWorkspace != originalWorkspace {
        _ = try controller.switchWorkspace(to: originalWorkspace)
    }
    return result
}

func makeSwitcherTestPreviewService(
    controller: WorkspaceController,
    captureImage: @escaping (WindowID) -> CGImage? = { _ in nil },
    renderWorkspace: @escaping (WorkspaceThumbnailRenderGroup) -> CGImage? = WorkspaceThumbnailRenderer.render,
    loadIcon: @escaping (pid_t) -> NSImage? = { _ in nil }
) -> SwitcherPreviewService {
    SwitcherPreviewService(
        controller: controller,
        windowThumbnailCache: WindowThumbnailCache(captureImage: captureImage),
        workspaceThumbnailCache: WorkspaceThumbnailCache(render: renderWorkspace),
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
    var shownWorkspaceIDs: [[String]] = []
    var reboundWorkspaceIDs: [[String]] = []
    var onWindowShown: (() -> Void)?
    var onWindowPreviewsUpdated: (() -> Void)?
    var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onWorkspaceKey: ((String) -> Bool)?

    func setInteractionHandlers(
        onArrowKey: @escaping (SwitcherArrowDirection) -> Void,
        onOutsideClick: @escaping () -> Void,
        onWorkspaceKey: @escaping (String) -> Bool
    ) {
        self.onArrowKey = onArrowKey
        self.onOutsideClick = onOutsideClick
        self.onWorkspaceKey = onWorkspaceKey
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

    func showWorkspaceSwitcher(
        groups: [WorkspaceSwitcherGroup],
        selectedID _: String,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (String) -> Void,
        onClick _: @escaping (String) -> Void
    ) {
        shownWorkspaceIDs.append(groups.map(\.id))
        isOverlayVisible = true
    }

    func rebindWorkspaceSwitcher(
        groups: [WorkspaceSwitcherGroup],
        selectedID _: String,
        anchorFrame _: WindowFrame?,
        onHover _: @escaping (String) -> Void,
        onClick _: @escaping (String) -> Void
    ) {
        reboundWorkspaceIDs.append(groups.map(\.id))
    }

    func updateWindowSwitcher(items: [WindowSwitcherItem]) {
        updatedWindowIDs.append(items.map(\.windowID))
        onWindowPreviewsUpdated?()
    }

    func updateWindowSelection(selectedID _: WindowID) {}

    func updateWorkspaceSwitcher(groups _: [WorkspaceSwitcherGroup]) {}

    func updateWorkspaceSelection(selectedID _: String) {}

    func hideOverlay() {
        isOverlayVisible = false
    }
}
