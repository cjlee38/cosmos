import Foundation

final class StartupHiddenWindowRecordApplier {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let configuration: WorkspaceConfigurationRuntime

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        configuration: WorkspaceConfigurationRuntime
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
        self.configuration = configuration
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        try windowStore.loadHiddenRecords()
    }

    func apply(
        records: [HiddenWindowRecord],
        state: inout WorkspaceState
    ) throws -> HiddenWindowRecordStartupApplyResult {
        var restored: [WindowID] = []
        var reassigned: [HiddenWindowRecordAssignment] = []
        var ignored: [HiddenWindowRecord] = []

        for record in records {
            let action = HiddenWindowRecordPolicy.startupAction(
                for: record,
                liveWindow: windowStore.windowSnapshotByID[record.windowID]
            )
            guard let targetWorkspace = action.workspace else {
                ignored.append(record)
                continue
            }

            let workspace = try configuration.ensureWorkspace(targetWorkspace, state: &state)
            if action.shouldRestore {
                try windowSystem.setPosition(record.originalFrame.origin, for: record.windowID)
                restored.append(record.windowID)
            }

            state.assign(record.windowID, to: workspace)
            reassigned.append(HiddenWindowRecordAssignment(windowID: record.windowID, workspace: workspace))
            windowStore.removeHiddenRecord(windowID: record.windowID, pid: record.pid)
        }

        windowStore.flushHiddenRecordWrites()
        return HiddenWindowRecordStartupApplyResult(restored: restored, reassigned: reassigned, ignored: ignored)
    }
}
