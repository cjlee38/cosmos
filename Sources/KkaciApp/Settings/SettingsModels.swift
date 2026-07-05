import Foundation
import KkaciCore

struct SettingsSnapshot {
    let config: KkaciConfig
    let configURL: URL?
    let activeWorkspace: String
    let activeWorkspaces: [String]
    let runtimeWorkspaces: [String]
    let monitorSlots: [MonitorSlotSnapshot]
    let monitorSlotsByWorkspace: [String: MonitorSlot]
}
