import Foundation

final class EmergencyHiddenWindowRestorer {
    private let recordRepository: HiddenWindowRecordRepository
    private let hiddenWindowOperator: HiddenWindowOperator

    init(recordRepository: HiddenWindowRecordRepository, hiddenWindowOperator: HiddenWindowOperator) {
        self.recordRepository = recordRepository
        self.hiddenWindowOperator = hiddenWindowOperator
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
                        let monitorSlot = state.monitorSlot(for: previousWorkspace)
                        state.assign(id, to: state.activeWorkspace(on: monitorSlot))
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
