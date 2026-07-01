import CoreGraphics
import Foundation
@testable import KkaciCore

final class FakeWindowSystem: WindowSystem {
    enum Operation: Equatable {
        case refresh
        case setPosition(WindowID, CGPoint)
        case setFrame(WindowID, WindowFrame)
        case focus(WindowID)
    }

    var windows: [WindowSnapshot]
    var focusedWindow: WindowID?
    var focusedIDs: [WindowID] = []
    var positions: [WindowID: CGPoint] = [:]
    var frames: [WindowID: WindowFrame] = [:]
    var operations: [Operation] = []
    var refreshCount = 0

    init(windows: [WindowSnapshot]) {
        self.windows = windows
        self.frames = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.frame.map { (window.id, $0) }
        })
    }

    func refresh() -> [WindowSnapshot] {
        refreshCount += 1
        operations.append(.refresh)
        return windows.map { snapshot in
            WindowSnapshot(
                id: snapshot.id,
                app: snapshot.app,
                title: snapshot.title,
                frame: frames[snapshot.id] ?? snapshot.frame,
                isMinimized: snapshot.isMinimized
            )
        }
    }

    func contains(_ id: WindowID) -> Bool {
        windows.contains { $0.id == id }
    }

    func focusedWindowID() -> WindowID? {
        focusedWindow
    }

    func snapshot(for id: WindowID) -> WindowSnapshot? {
        windows.first { $0.id == id }.map { snapshot in
            WindowSnapshot(
                id: snapshot.id,
                app: snapshot.app,
                title: snapshot.title,
                frame: frames[snapshot.id] ?? snapshot.frame,
                isMinimized: snapshot.isMinimized
            )
        }
    }

    func frame(for id: WindowID) -> WindowFrame? {
        frames[id]
    }

    func setPosition(_ point: CGPoint, for id: WindowID) throws {
        operations.append(.setPosition(id, point))
        positions[id] = point
        if var frame = frames[id] {
            frame.origin = point
            frames[id] = frame
        }
    }

    func setFrame(_ frame: WindowFrame, for id: WindowID) throws {
        operations.append(.setFrame(id, frame))
        frames[id] = frame
        positions[id] = frame.origin
    }

    func focus(_ id: WindowID) {
        operations.append(.focus(id))
        focusedWindow = id
        focusedIDs.append(id)
    }
}
