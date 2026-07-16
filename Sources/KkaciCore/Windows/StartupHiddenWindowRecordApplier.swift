import Foundation

final class StartupHiddenWindowRecordApplier {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let recordRepository: HiddenWindowRecordRepository
    private let restorableFrameResolver: RestorableFrameResolver

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        recordRepository: HiddenWindowRecordRepository,
        restorableFrameResolver: RestorableFrameResolver
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
        self.recordRepository = recordRepository
        self.restorableFrameResolver = restorableFrameResolver
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        try recordRepository.loadRecords()
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
                liveWindow: windowStore.snapshot(for: record.windowID)
            )
            guard let targetWorkspace = action.workspace else {
                ignored.append(record)
                continue
            }

            let workspace = state.findWorkspace(targetWorkspace) ?? state.activeWorkspace
            if action.shouldRestore {
                try windowSystem.setFrameIfSizeChanged(
                    restorableFrameResolver.frameForRestore(record.originalFrame),
                    for: record.windowID
                )
                restored.append(record.windowID)
            }

            state.assign(record.windowID, to: workspace)
            reassigned.append(HiddenWindowRecordAssignment(windowID: record.windowID, workspace: workspace))
            recordRepository.removeRecord(windowID: record.windowID, pid: record.pid)
        }

        try recordRepository.flushPendingWrites()
        return HiddenWindowRecordStartupApplyResult(restored: restored, reassigned: reassigned, ignored: ignored)
    }
}
