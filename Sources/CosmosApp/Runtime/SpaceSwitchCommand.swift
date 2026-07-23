import CoreGraphics
import CosmosCore

final class SpaceSwitchCommand {
    private let log = Log(category: "space")

    private let controller: SpaceController
    private let warpCursor: (CGPoint) -> CGError

    init(
        controller: SpaceController,
        warpCursor: @escaping (CGPoint) -> CGError = CGWarpMouseCursorPosition
    ) {
        self.controller = controller
        self.warpCursor = warpCursor
    }

    @discardableResult
    func execute(to space: String) throws -> Bool {
        let sourceMonitorSlot = controller.effectiveMonitorSlot(for: controller.currentSpace)
        guard try controller.switchSpace(to: space) != nil else {
            return false
        }

        let targetMonitorSlot = controller.effectiveMonitorSlot(for: space)
        guard sourceMonitorSlot != targetMonitorSlot,
              let targetDisplay = controller.displayTopology.monitorSlots.first(where: {
                  $0.slot == targetMonitorSlot
              })?.display
        else {
            return true
        }

        let center = CGPoint(x: targetDisplay.frame.midX, y: targetDisplay.frame.midY)
        let error = warpCursor(center)
        if error != .success {
            log.warning("Cursor follow failed: \(error.rawValue)")
        }
        return true
    }
}
