import Foundation

enum WindowFrameObservationError: Error, CustomStringConvertible {
    case unavailable(operation: String, windowID: WindowID)
    case rejected(operation: String, windowID: WindowID, actual: WindowFrame)

    var description: String {
        switch self {
        case let .unavailable(operation, windowID):
            "\(operation) could not read the resulting frame for window \(windowID)"
        case let .rejected(operation, windowID, actual):
            "\(operation) did not reach its semantic target for window \(windowID): \(actual)"
        }
    }
}

final class WindowFrameApplicationEvaluator {
    private let windowCache: WindowStateCache
    private let hidePointProvider: any HidePointProviding

    init(
        windowCache: WindowStateCache,
        hidePointProvider: any HidePointProviding
    ) {
        self.windowCache = windowCache
        self.hidePointProvider = hidePointProvider
    }

    func parkedFrame(
        _ observation: WindowFrameWriteObservation,
        operation: String,
        windowID: WindowID,
        targetFrame: WindowFrame
    ) throws -> WindowFrame {
        guard let actualFrame = observation.actualFrame else {
            return targetFrame
        }
        guard hidePointProvider.isHidePosition(
            actualFrame,
            displays: windowCache.displayTopology.displays
        ) else {
            throw WindowFrameObservationError.rejected(
                operation: operation,
                windowID: windowID,
                actual: actualFrame
            )
        }
        return actualFrame
    }

    func visibleFrame(
        _ observation: WindowFrameWriteObservation,
        operation: String,
        windowID: WindowID,
        targetFrame: WindowFrame
    ) throws -> WindowFrame {
        guard let actualFrame = observation.actualFrame else {
            throw WindowFrameObservationError.unavailable(
                operation: operation,
                windowID: windowID
            )
        }
        guard isVisible(actualFrame, for: targetFrame) else {
            throw WindowFrameObservationError.rejected(
                operation: operation,
                windowID: windowID,
                actual: actualFrame
            )
        }
        return actualFrame
    }

    func observedFrame(
        _ observation: WindowFrameWriteObservation,
        targetFrame: WindowFrame
    ) -> WindowFrame {
        observation.actualFrame ?? targetFrame
    }

    private func isVisible(
        _ actualFrame: WindowFrame,
        for targetFrame: WindowFrame
    ) -> Bool {
        let displays = windowCache.displayTopology.displays
        guard !hidePointProvider.isHidePosition(actualFrame, displays: displays),
              let targetDisplay = DisplayGeometry.display(
                  containingOrNearest: targetFrame.center,
                  among: displays
              )
        else {
            return false
        }
        return targetDisplay.frame.contains(actualFrame.center)
    }
}
