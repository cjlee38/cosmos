import Foundation

struct WorkspaceControllerComponents {
    let windowCache: WindowStateCache
    let runtimeSynchronizer: WorkspaceRuntimeSynchronizer
    let hiddenWindowOperator: HiddenWindowOperator
    let visibilityCoordinator: WorkspaceVisibilityCoordinator
    let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    let navigationCoordinator: WorkspaceNavigationCoordinator
    let assignmentCoordinator: WindowAssignmentCoordinator
    let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    let displayCoordinator: WorkspaceDisplayCoordinator
    let startupConfigLoadError: Error?
    let state: WorkspaceState
}

enum WorkspaceControllerComposition {
    static func build(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)?,
        configStore: (any KkaciConfigStore)?,
        recordStore: (any HiddenWindowRecordStore)?
    ) -> WorkspaceControllerComponents {
        let windows = buildWindowComponents(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: hidePointProvider,
            recordStore: recordStore
        )
        let startup = loadConfig(from: configStore)

        return WorkspaceControllerComponents(
            windowCache: windows.cache,
            runtimeSynchronizer: windows.synchronizer,
            hiddenWindowOperator: windows.hiddenOperator,
            visibilityCoordinator: windows.visibilityCoordinator,
            startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier(
                windowSystem: windowSystem,
                windowCache: windows.cache,
                recordRepository: windows.recordRepository,
                restorableFrameResolver: RestorableFrameResolver(displayProvider: displayProvider)
            ),
            navigationCoordinator: WorkspaceNavigationCoordinator(
                windowCache: windows.cache,
                visibilityCoordinator: windows.visibilityCoordinator
            ),
            assignmentCoordinator: WindowAssignmentCoordinator(
                windowCache: windows.cache,
                visibilityCoordinator: windows.visibilityCoordinator,
                monitorSlotResolver: windows.monitorSlotResolver
            ),
            emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer(
                recordRepository: windows.recordRepository,
                hiddenWindowOperator: windows.hiddenOperator,
                windowCache: windows.cache
            ),
            displayCoordinator: WorkspaceDisplayCoordinator(
                windowCache: windows.cache,
                runtimeSynchronizer: windows.synchronizer,
                monitorSlotResolver: windows.monitorSlotResolver
            ),
            startupConfigLoadError: startup.error,
            state: WorkspaceState(config: startup.config)
        )
    }

    private static func loadConfig(
        from store: (any KkaciConfigStore)?
    ) -> (config: KkaciConfig, error: Error?) {
        guard let store else {
            return (.default, nil)
        }
        do {
            return try (store.load(), nil)
        } catch {
            return (.default, error)
        }
    }

    private static func buildWindowComponents(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)?,
        recordStore: (any HiddenWindowRecordStore)?
    ) -> WorkspaceControllerWindowComponents {
        let cache = WindowStateCache()
        let recordRepository = HiddenWindowRecordRepository(store: recordStore)
        let monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        let synchronizer = WorkspaceRuntimeSynchronizer(
            windowSystem: windowSystem,
            windowCache: cache,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver
        )
        let hiddenOperator = HiddenWindowOperator(
            windowSystem: windowSystem,
            hidePointProvider: hidePointProvider ?? WindowParkingPointProvider(displayProvider: displayProvider),
            restorableFrameResolver: RestorableFrameResolver(displayProvider: displayProvider),
            windowCache: cache,
            recordRepository: recordRepository
        )
        return WorkspaceControllerWindowComponents(
            cache: cache,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver,
            synchronizer: synchronizer,
            hiddenOperator: hiddenOperator,
            visibilityCoordinator: WorkspaceVisibilityCoordinator(
                windowSystem: windowSystem,
                hiddenWindowOperator: hiddenOperator,
                windowCache: cache
            )
        )
    }
}

private struct WorkspaceControllerWindowComponents {
    let cache: WindowStateCache
    let recordRepository: HiddenWindowRecordRepository
    let monitorSlotResolver: MonitorSlotResolver
    let synchronizer: WorkspaceRuntimeSynchronizer
    let hiddenOperator: HiddenWindowOperator
    let visibilityCoordinator: WorkspaceVisibilityCoordinator
}
