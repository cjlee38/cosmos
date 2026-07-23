import CosmosCore

enum DisplayListFormatter {
    static func lines(for topology: DisplayTopologySnapshot) -> [String] {
        topology.monitorSlots.sorted { $0.slot < $1.slot }.map { monitor in
            "\(monitor.slot) (\(monitor.display.name))  \(roleName(monitor.display.role))"
        }
    }

    private static func roleName(_ role: DisplayRole) -> String {
        switch role {
        case .main:
            "Main"
        case .extended:
            "Extended"
        }
    }
}
