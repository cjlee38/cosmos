import Foundation

final class StartupHiddenWindowRecordApplier {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository
    private let restorableFrameResolver: RestorableFrameResolver

    init(
        windowSystem: any WindowSystem,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository,
        restorableFrameResolver: RestorableFrameResolver
    ) {
        self.windowSystem = windowSystem
        self.windowCache = windowCache
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
        var failed: [WindowID] = []

        for record in records {
            let action = HiddenWindowRecordPolicy.startupAction(
                for: record,
                liveWindow: windowCache.snapshot(for: record.windowID)
            )
            guard let targetWorkspace = action.workspace else {
                ignored.append(record)
                continue
            }

            let workspace = state.containsWorkspace(targetWorkspace) ? targetWorkspace : state.currentWorkspace
            if action.shouldRestore {
                do {
                    try windowSystem.setFrameOrMove(
                        restorableFrameResolver.frameForRestore(record.originalFrame),
                        for: record.windowID
                    )
                } catch {
                    failed.append(record.windowID)
                    continue
                }
                restored.append(record.windowID)
            }

            state.assign(record.windowID, to: workspace)
            reassigned.append(HiddenWindowRecordAssignment(
                windowID: record.windowID,
                workspace: workspace
            ))
            recordRepository.removeRecord(windowID: record.windowID, pid: record.pid)
        }

        try recordRepository.flushPendingWrites()
        return HiddenWindowRecordStartupApplyResult(
            restored: restored,
            reassigned: reassigned,
            ignored: ignored,
            failed: failed
        )
    }
}
