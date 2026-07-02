import AppKit

final class ModifierReleaseMonitor {
    private let onFlagsChanged: (NSEvent.ModifierFlags) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void) {
        self.onFlagsChanged = onFlagsChanged
    }

    deinit {
        stop()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged(event.modifierFlags)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged(event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
