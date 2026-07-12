import AppKit

final class ApplicationIconCache {
    private let loadIcon: (pid_t) -> NSImage?
    private let loadQueue = DispatchQueue(label: "kkaci.application-icons", qos: .userInitiated)
    private var iconsByPID: [pid_t: NSImage] = [:]
    private var inFlight: Set<pid_t> = []

    init(loadIcon: @escaping (pid_t) -> NSImage? = { pid in
        NSRunningApplication(processIdentifier: pid)?.icon
    }) {
        self.loadIcon = loadIcon
    }

    func icon(for pid: pid_t) -> NSImage? {
        iconsByPID[pid]
    }

    func refresh(
        pids: Set<pid_t>,
        onIconUpdated: @escaping (pid_t) -> Void = { _ in }
    ) {
        iconsByPID = iconsByPID.filter { pids.contains($0.key) }
        inFlight = inFlight.intersection(pids)

        let pendingPIDs = pids.filter { pid in
            iconsByPID[pid] == nil && inFlight.insert(pid).inserted
        }
        for pid in pendingPIDs {
            loadQueue.async { [loadIcon] in
                let icon = loadIcon(pid)
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }

                    inFlight.remove(pid)
                    guard let icon else {
                        return
                    }

                    iconsByPID[pid] = icon
                    onIconUpdated(pid)
                }
            }
        }
    }
}
