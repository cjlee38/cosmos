import CoreGraphics
@testable import CosmosCore
import XCTest

final class WindowSystemTests: XCTestCase {
    func testFrameUpdateFallsBackToPositionAfterPartialFrameMutation() throws {
        let originalFrame = WindowFrame.frame(x: 10, y: 10)
        let targetFrame = WindowFrame.frame(x: 200, y: 200, width: 300, height: 300)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: originalFrame)
        ])
        var failedInitialFrameWrite = false
        windowSystem.operationFailureAfterMutation = { operation in
            guard case .setFrame = operation, !failedInitialFrameWrite else {
                return nil
            }
            failedInitialFrameWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }

        let appliedFrame = try windowSystem.setFrameOrMove(targetFrame, for: 100)

        XCTAssertEqual(appliedFrame, .exact(actual: targetFrame))
        XCTAssertEqual(windowSystem.frames[100], targetFrame)
    }

    func testFrameUpdateReportsTheObservedFrameWhenTheWindowAdjustsTheRequest() throws {
        let originalFrame = WindowFrame.frame(x: 10, y: 10)
        let targetFrame = WindowFrame.frame(x: 200, y: 200, width: 300, height: 300)
        let adjustedFrame = WindowFrame.frame(x: 200, y: 200, width: 280, height: 290)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: originalFrame)
        ])
        windowSystem.appliedFrame = { _, _ in adjustedFrame }

        let observation = try windowSystem.setFrameOrMove(targetFrame, for: 100)

        XCTAssertEqual(observation, .different(actual: adjustedFrame))
    }

    func testPositionUpdateReportsUnavailableWhenTheResultCannotBeRead() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 10, y: 10))
        ])
        windowSystem.unavailableFrameReads.insert(100)

        let observation = try windowSystem.setPositionAndObserve(CGPoint(x: 200, y: 200), for: 100)

        XCTAssertEqual(observation, .unavailable)
    }

    func testFrameUpdateRollsBackPartialMutationWhenPositionFallbackFails() {
        let originalFrame = WindowFrame.frame(x: 10, y: 10)
        let targetFrame = WindowFrame.frame(x: 200, y: 200, width: 300, height: 300)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: originalFrame)
        ])
        var failedInitialFrameWrite = false
        windowSystem.operationFailureAfterMutation = { operation in
            guard case .setFrame = operation, !failedInitialFrameWrite else {
                return nil
            }
            failedInitialFrameWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }
        windowSystem.operationFailure = { operation in
            guard case .setPosition = operation else {
                return nil
            }
            return FakeWindowSystemError.frameWrite(100)
        }

        XCTAssertThrowsError(try windowSystem.setFrameOrMove(targetFrame, for: 100))
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testFrameUpdateReportsApplyAndRollbackFailures() {
        let originalFrame = WindowFrame.frame(x: 10, y: 10)
        let targetFrame = WindowFrame.frame(x: 200, y: 200, width: 300, height: 300)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: originalFrame)
        ])
        var failedInitialFrameWrite = false
        windowSystem.operationFailureAfterMutation = { operation in
            guard case .setFrame = operation, !failedInitialFrameWrite else {
                return nil
            }
            failedInitialFrameWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }
        windowSystem.operationFailure = { operation in
            switch operation {
            case .setPosition:
                FakeWindowSystemError.frameWrite(100)
            case .setFrame where failedInitialFrameWrite:
                FakeWindowSystemError.frameWrite(100)
            case .refresh, .setFrame, .focus:
                nil
            }
        }

        XCTAssertThrowsError(try windowSystem.setFrameOrMove(targetFrame, for: 100)) { error in
            XCTAssertTrue(error is WindowFrameTransactionError)
        }
        XCTAssertEqual(windowSystem.frames[100], targetFrame)
    }
}
