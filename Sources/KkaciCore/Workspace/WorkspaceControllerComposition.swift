import Foundation

struct WorkspaceControllerComponents {
    let windowStore: WindowRuntimeStore
    let configuration: WorkspaceConfigurationRuntime
    let windowSetSynchronizer: WindowSetSynchronizer
    let hiddenWindowOperator: HiddenWindowOperator
    let visibilityCoordinator: WorkspaceVisibilityCoordinator
    let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    let navigationCoordinator: WorkspaceNavigationCoordinator
    let assignmentCoordinator: WindowAssignmentCoordinator
    let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    let monitorSlotResolver: MonitorSlotResolver
    let displayCoordinator: WorkspaceDisplayCoordinator
    let state: WorkspaceState
}

enum WorkspaceControllerComposition {
    static func build(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        configStore: (any KkaciConfigStore)?,
        recordStore: (any HiddenWindowRecordStore)?,
        isConfigPersistenceEnabled: Bool
    ) -> WorkspaceControllerComponents {
        let windows = buildWindowComponents(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            recordStore: recordStore
        )
        let bootstrap = WorkspaceConfigurationRuntime.bootstrap(
            from: configStore,
            isPersistenceEnabled: isConfigPersistenceEnabled
        )

        return WorkspaceControllerComponents(
            windowStore: windows.store,
            configuration: bootstrap.runtime,
            windowSetSynchronizer: windows.synchronizer,
            hiddenWindowOperator: windows.hiddenOperator,
            visibilityCoordinator: windows.visibilityCoordinator,
            startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier(
                windowSystem: windowSystem,
                windowStore: windows.store,
                recordRepository: windows.recordRepository,
                restorableFrameResolver: RestorableFrameResolver(displayProvider: displayProvider)
            ),
            navigationCoordinator: WorkspaceNavigationCoordinator(
                windowSystem: windowSystem,
                windowStore: windows.store,
                visibilityCoordinator: windows.visibilityCoordinator
            ),
            assignmentCoordinator: WindowAssignmentCoordinator(
                windowSystem: windowSystem,
                windowStore: windows.store,
                visibilityCoordinator: windows.visibilityCoordinator,
                monitorSlotResolver: windows.monitorSlotResolver
            ),
            emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer(
                recordRepository: windows.recordRepository,
                hiddenWindowOperator: windows.hiddenOperator,
                windowStore: windows.store
            ),
            monitorSlotResolver: windows.monitorSlotResolver,
            displayCoordinator: WorkspaceDisplayCoordinator(
                windowStore: windows.store,
                windowSetSynchronizer: windows.synchronizer,
                visibilityCoordinator: windows.visibilityCoordinator,
                monitorSlotResolver: windows.monitorSlotResolver
            ),
            state: WorkspaceState(workspaces: bootstrap.config.workspaces)
        )
    }

    private static func buildWindowComponents(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        recordStore: (any HiddenWindowRecordStore)?
    ) -> WorkspaceControllerWindowComponents {
        let store = WindowRuntimeStore()
        let recordRepository = HiddenWindowRecordRepository(store: recordStore)
        let monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        let synchronizer = WindowSetSynchronizer(
            windowSystem: windowSystem,
            windowStore: store,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver
        )
        let hiddenOperator = HiddenWindowOperator(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            restorableFrameResolver: RestorableFrameResolver(displayProvider: displayProvider),
            windowStore: store,
            recordRepository: recordRepository
        )
        return WorkspaceControllerWindowComponents(
            store: store,
            recordRepository: recordRepository,
            monitorSlotResolver: monitorSlotResolver,
            synchronizer: synchronizer,
            hiddenOperator: hiddenOperator,
            visibilityCoordinator: WorkspaceVisibilityCoordinator(
                windowSystem: windowSystem,
                hiddenWindowOperator: hiddenOperator,
                windowStore: store
            )
        )
    }
}

private struct WorkspaceControllerWindowComponents {
    let store: WindowRuntimeStore
    let recordRepository: HiddenWindowRecordRepository
    let monitorSlotResolver: MonitorSlotResolver
    let synchronizer: WindowSetSynchronizer
    let hiddenOperator: HiddenWindowOperator
    let visibilityCoordinator: WorkspaceVisibilityCoordinator
}
