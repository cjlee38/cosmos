import CoreGraphics
@testable import CosmosCore
import Foundation

enum FakeWindowSystemError: Error, Equatable {
    case refresh
    case frameWrite(WindowID)
}

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
    var unavailableFrameReads: Set<WindowID> = []
    var operations: [Operation] = []
    var frameWriteFailures: Set<WindowID> = []
    var operationFailure: ((Operation) -> Error?)?
    var operationFailureAfterMutation: ((Operation) -> Error?)?
    var discoveryApplyResults: [Bool] = []
    var refreshCount = 0
    var refreshError: Error?

    init(windows: [WindowSnapshot]) {
        self.windows = windows
        frames = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.frame.map { (window.id, $0) }
        })
    }

    func refresh() throws -> [WindowSnapshot] {
        refreshCount += 1
        operations.append(.refresh)
        if let refreshError {
            throw refreshError
        }
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

    func apply(_: WindowDiscoverySnapshot) -> Bool {
        discoveryApplyResults.isEmpty ? true : discoveryApplyResults.removeFirst()
    }

    func frame(for id: WindowID) -> WindowFrame? {
        guard !unavailableFrameReads.contains(id) else {
            return nil
        }
        return frames[id]
    }

    func setPosition(_ point: CGPoint, for id: WindowID) throws {
        guard contains(id) else {
            throw SpaceError.windowNotFound(id)
        }
        let operation = Operation.setPosition(id, point)
        operations.append(operation)
        if let error = operationFailure?(operation) {
            throw error
        }
        if frameWriteFailures.contains(id) {
            throw FakeWindowSystemError.frameWrite(id)
        }

        positions[id] = point
        if var frame = frames[id] {
            frame.origin = point
            frames[id] = frame
        }
        if let error = operationFailureAfterMutation?(operation) {
            throw error
        }
    }

    func setFrame(_ frame: WindowFrame, for id: WindowID) throws {
        guard contains(id) else {
            throw SpaceError.windowNotFound(id)
        }
        let operation = Operation.setFrame(id, frame)
        operations.append(operation)
        if let error = operationFailure?(operation) {
            throw error
        }
        if frameWriteFailures.contains(id) {
            throw FakeWindowSystemError.frameWrite(id)
        }

        positions[id] = frame.origin
        frames[id] = frame
        if let error = operationFailureAfterMutation?(operation) {
            throw error
        }
    }

    func focus(_ id: WindowID) {
        guard contains(id) else {
            return
        }
        operations.append(.focus(id))
        focusedWindow = id
        focusedIDs.append(id)
    }
}
