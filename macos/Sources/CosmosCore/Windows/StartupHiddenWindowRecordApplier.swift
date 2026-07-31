import Foundation

final class StartupHiddenWindowRecordApplier {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository
    private let hidePointProvider: any HidePointProviding
    private let restorableFrameResolver: RestorableFrameResolver
    private let frameApplicationEvaluator: WindowFrameApplicationEvaluator

    init(
        windowSystem: any WindowSystem,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository,
        hidePointProvider: any HidePointProviding,
        restorableFrameResolver: RestorableFrameResolver,
        frameApplicationEvaluator: WindowFrameApplicationEvaluator
    ) {
        self.windowSystem = windowSystem
        self.windowCache = windowCache
        self.recordRepository = recordRepository
        self.hidePointProvider = hidePointProvider
        self.restorableFrameResolver = restorableFrameResolver
        self.frameApplicationEvaluator = frameApplicationEvaluator
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        try recordRepository.loadRecords()
    }

    func apply(
        records: [HiddenWindowRecord],
        state: inout SpaceState
    ) throws -> HiddenWindowRecordStartupApplyResult {
        var restored: [WindowID] = []
        var reassigned: [HiddenWindowRecordAssignment] = []
        var ignored: [HiddenWindowRecord] = []
        var failed: [WindowID] = []

        for record in records {
            let liveWindow = windowCache.snapshot(for: record.windowID)
            let isAtHidePosition = liveWindow?.frame.map {
                hidePointProvider.isHidePosition(
                    $0,
                    displays: windowCache.displayTopology.displays
                )
            } ?? false
            let action = HiddenWindowRecordPolicy.startupAction(
                for: record,
                liveWindow: liveWindow,
                isAtHidePosition: isAtHidePosition
            )
            guard let targetSpace = action.space else {
                ignored.append(record)
                continue
            }

            let space = state.containsSpace(targetSpace) ? targetSpace : state.currentSpace
            if action.shouldRestore {
                do {
                    try restoreRecord(record)
                } catch {
                    failed.append(record.windowID)
                    continue
                }
                restored.append(record.windowID)
            }

            state.assign(record.windowID, to: space)
            reassigned.append(HiddenWindowRecordAssignment(
                windowID: record.windowID,
                space: space
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

    private func restoreRecord(_ record: HiddenWindowRecord) throws {
        let targetFrame = try restorableFrameResolver.frameForRestore(record.originalFrame)
        let observation = try windowSystem.setFrameOrMove(targetFrame, for: record.windowID)
        _ = try frameApplicationEvaluator.visibleFrame(
            observation,
            operation: "restore-startup-record",
            windowID: record.windowID,
            targetFrame: targetFrame
        )
    }
}
