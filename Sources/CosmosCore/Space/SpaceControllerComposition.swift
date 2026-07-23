import Foundation

struct SpaceControllerComponents {
    let windowCache: WindowStateCache
    let runtimeSynchronizer: SpaceRuntimeSynchronizer
    let hiddenWindowOperator: HiddenWindowOperator
    let visibilityCoordinator: SpaceVisibilityCoordinator
    let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    let navigationCoordinator: SpaceNavigationCoordinator
    let assignmentCoordinator: WindowAssignmentCoordinator
    let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    let displayCoordinator: SpaceDisplayCoordinator
    let startupConfigLoadError: Error?
    let state: SpaceState
}

enum SpaceControllerComposition {
    static func build(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)?,
        configStore: (any CosmosConfigStore)?,
        recordStore: (any HiddenWindowRecordStore)?
    ) -> SpaceControllerComponents {
        let windows = buildWindowComponents(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: hidePointProvider,
            recordStore: recordStore
        )
        let startup = loadConfig(from: configStore)

        return SpaceControllerComponents(
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
            navigationCoordinator: SpaceNavigationCoordinator(
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
            displayCoordinator: SpaceDisplayCoordinator(
                windowCache: windows.cache,
                runtimeSynchronizer: windows.synchronizer,
                monitorSlotResolver: windows.monitorSlotResolver
            ),
            startupConfigLoadError: startup.error,
            state: SpaceState(config: startup.config)
        )
    }

    private static func loadConfig(
        from store: (any CosmosConfigStore)?
    ) -> (config: CosmosConfig, error: Error?) {
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
    ) -> SpaceControllerWindowComponents {
        let cache = WindowStateCache()
        let recordRepository = HiddenWindowRecordRepository(store: recordStore)
        let monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        let synchronizer = SpaceRuntimeSynchronizer(
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
        return SpaceControllerWindowComponents(
            cache: cache,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver,
            synchronizer: synchronizer,
            hiddenOperator: hiddenOperator,
            visibilityCoordinator: SpaceVisibilityCoordinator(
                windowSystem: windowSystem,
                hiddenWindowOperator: hiddenOperator,
                windowCache: cache
            )
        )
    }
}

private struct SpaceControllerWindowComponents {
    let cache: WindowStateCache
    let recordRepository: HiddenWindowRecordRepository
    let monitorSlotResolver: MonitorSlotResolver
    let synchronizer: SpaceRuntimeSynchronizer
    let hiddenOperator: HiddenWindowOperator
    let visibilityCoordinator: SpaceVisibilityCoordinator
}
