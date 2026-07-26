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
    let startupSessionStateLoadError: Error?
    let sessionStateStore: (any SessionStateStore)?
    let loadedSessionState: SessionState?
    let state: SpaceState
}

enum SpaceControllerComposition {
    static func build(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)?,
        configStore: (any CosmosConfigStore)?,
        sessionStateStore: (any SessionStateStore)?
    ) -> SpaceControllerComponents {
        let windows = buildWindowComponents(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: hidePointProvider,
            sessionStateStore: sessionStateStore
        )
        let startup = loadConfig(from: configStore)
        let sessionStartup = loadSessionState(from: sessionStateStore)

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
                monitorSlotResolver: windows.monitorSlotResolver,
                hidePointProvider: windows.hidePointProvider
            ),
            startupConfigLoadError: startup.error,
            startupSessionStateLoadError: sessionStartup.error,
            sessionStateStore: sessionStateStore,
            loadedSessionState: sessionStartup.state,
            state: SpaceState(config: startup.config, sessionState: sessionStartup.state)
        )
    }

    private static func loadSessionState(
        from store: (any SessionStateStore)?
    ) -> (state: SessionState?, error: Error?) {
        guard let store else {
            return (nil, nil)
        }
        do {
            return try (store.load(), nil)
        } catch {
            return (nil, error)
        }
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
        sessionStateStore: (any SessionStateStore)?
    ) -> SpaceControllerWindowComponents {
        let cache = WindowStateCache()
        let recordRepository = HiddenWindowRecordRepository(store: sessionStateStore)
        let monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        let hidePointProvider =
            hidePointProvider ?? WindowParkingPointProvider(displayProvider: displayProvider)
        let synchronizer = SpaceRuntimeSynchronizer(
            windowSystem: windowSystem,
            windowCache: cache,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver,
            hidePointProvider: hidePointProvider
        )
        let hiddenOperator = HiddenWindowOperator(
            windowSystem: windowSystem,
            hidePointProvider: hidePointProvider,
            restorableFrameResolver: RestorableFrameResolver(displayProvider: displayProvider),
            windowCache: cache,
            recordRepository: recordRepository
        )
        return SpaceControllerWindowComponents(
            cache: cache,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver,
            hidePointProvider: hidePointProvider,
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
    let hidePointProvider: any HidePointProviding
    let synchronizer: SpaceRuntimeSynchronizer
    let hiddenOperator: HiddenWindowOperator
    let visibilityCoordinator: SpaceVisibilityCoordinator
}
