import Foundation

final class EmergencyHiddenWindowRestorer {
    private let recordRepository: HiddenWindowRecordRepository
    private let hiddenWindowOperator: HiddenWindowOperator
    private let windowCache: WindowStateCache

    init(
        recordRepository: HiddenWindowRecordRepository,
        hiddenWindowOperator: HiddenWindowOperator,
        windowCache: WindowStateCache
    ) {
        self.recordRepository = recordRepository
        self.hiddenWindowOperator = hiddenWindowOperator
        self.windowCache = windowCache
    }

    func restoreAll(
        requestedIDs: [WindowID],
        state: inout WorkspaceState
    ) throws -> RestoreAllHiddenWindowsResult {
        var restored: [WindowID] = []
        var unavailable: [WindowID] = []
        var failed: [WindowID] = []

        for id in requestedIDs {
            guard state.hiddenFrame(for: id) != nil else {
                recordRepository.removeAllRecords(for: id)
                unavailable.append(id)
                continue
            }
            do {
                if try hiddenWindowOperator.restore(id, state: &state) == .restored {
                    if let previousWorkspace = state.membership(for: id) {
                        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
                        let monitorSlot = state.monitorSlot(
                            for: previousWorkspace,
                            availableMonitorSlots: availableMonitorSlots
                        )
                        state.assign(
                            id,
                            to: state.visibleWorkspace(
                                on: monitorSlot,
                                availableMonitorSlots: availableMonitorSlots
                            )
                        )
                    }
                    restored.append(id)
                }
            } catch WorkspaceError.windowNotFound {
                recordRepository.removeAllRecords(for: id)
                unavailable.append(id)
            } catch {
                failed.append(id)
            }
        }

        try recordRepository.flushPendingWrites()
        return RestoreAllHiddenWindowsResult(
            restored: restored,
            unavailable: unavailable,
            failed: failed
        )
    }
}
