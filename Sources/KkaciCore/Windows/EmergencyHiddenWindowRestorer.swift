import Foundation

final class EmergencyHiddenWindowRestorer {
    private let recordRepository: HiddenWindowRecordRepository
    private let hiddenWindowOperator: HiddenWindowOperator
    private let windowStore: WindowRuntimeStore

    init(
        recordRepository: HiddenWindowRecordRepository,
        hiddenWindowOperator: HiddenWindowOperator,
        windowStore: WindowRuntimeStore
    ) {
        self.recordRepository = recordRepository
        self.hiddenWindowOperator = hiddenWindowOperator
        self.windowStore = windowStore
    }

    func restoreAll(
        requestedIDs: [WindowID],
        state: inout WorkspaceState
    ) throws -> RestoreAllHiddenWindowsResult {
        var restored: [WindowID] = []
        var skipped: [WindowID] = []

        for id in requestedIDs {
            guard state.hiddenFrame(for: id) != nil else {
                recordRepository.removeAllRecords(for: id)
                skipped.append(id)
                continue
            }
            do {
                if try hiddenWindowOperator.restore(id, state: &state) == .restored {
                    if let previousWorkspace = state.membership(for: id) {
                        let availableMonitorSlots = windowStore.displayTopology.availableMonitorSlots
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
                skipped.append(id)
            } catch {
                skipped.append(id)
            }
        }

        try recordRepository.flushPendingWrites()
        return RestoreAllHiddenWindowsResult(restored: restored, skipped: skipped)
    }
}
