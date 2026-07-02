import Foundation

final class EmergencyHiddenWindowRestorer {
    private let windowStore: WindowRuntimeStore
    private let hiddenWindowOperator: HiddenWindowOperator

    init(windowStore: WindowRuntimeStore, hiddenWindowOperator: HiddenWindowOperator) {
        self.windowStore = windowStore
        self.hiddenWindowOperator = hiddenWindowOperator
    }

    func restoreAll(
        requestedIDs: [WindowID],
        state: inout WorkspaceState
    ) -> RestoreAllHiddenWindowsResult {
        var restored: [WindowID] = []
        var skipped: [WindowID] = []

        for id in requestedIDs {
            guard state.hiddenFrame(for: id) != nil else {
                windowStore.removeAllHiddenRecords(for: id)
                skipped.append(id)
                continue
            }
            do {
                if try hiddenWindowOperator.restore(id, state: &state) == .restored {
                    restored.append(id)
                }
            } catch WorkspaceError.windowNotFound {
                windowStore.removeAllHiddenRecords(for: id)
                skipped.append(id)
            } catch {
                skipped.append(id)
            }
        }

        windowStore.flushHiddenRecordWrites()
        return RestoreAllHiddenWindowsResult(restored: restored, skipped: skipped)
    }
}
