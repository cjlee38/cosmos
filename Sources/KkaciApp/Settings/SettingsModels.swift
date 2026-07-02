import Foundation
import KkaciCore

struct SettingsSnapshot {
    let config: KkaciConfig
    let configURL: URL?
    let activeWorkspace: String
    let runtimeWorkspaces: [String]
}
