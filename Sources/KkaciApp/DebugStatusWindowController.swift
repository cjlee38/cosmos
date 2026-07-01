import AppKit
import KkaciCore

final class DebugStatusWindowController: NSWindowController {
    private let controller: WorkspaceController
    private let lastMessage: () -> String
    private let textView = NSTextView()

    init(controller: WorkspaceController, lastMessage: @escaping () -> String) {
        self.controller = controller
        self.lastMessage = lastMessage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "kkaci Debug Status"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        textView.string = renderStatus()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 780, height: 440)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        let refreshButton = NSButton(
            title: "Refresh",
            target: self,
            action: #selector(refreshButtonClicked)
        )
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(
            title: "Close",
            target: self,
            action: #selector(closeButtonClicked)
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(refreshButton)
        contentView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -12),

            refreshButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            refreshButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            closeButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            closeButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor),
        ])
    }

    private func renderStatus() -> String {
        let result = controller.listWindows()
        let focused = controller.focusedWindowID()

        var lines: [String] = [
            "kkaci debug status",
            "active workspace: \(controller.activeWorkspace)",
            "workspaces: \(controller.workspaces.joined(separator: ", "))",
            "last message: \(lastMessage())",
            "",
        ]

        if !result.sync.isEmpty {
            lines.append("sync:")
            for (id, workspace) in result.sync.autoAssigned {
                lines.append("  auto-assigned \(id) -> \(workspace)")
            }
            for id in result.sync.removed {
                lines.append("  removed \(id)")
            }
            lines.append("")
        }

        lines.append("windows:")
        if result.windows.isEmpty {
            lines.append("  (none)")
        } else {
            for window in result.windows {
                let marker = window.id == focused ? "*" : " "
                let workspace = controller.membership(for: window.id) ?? "-"
                let hidden = controller.isHiddenByWorkspace(window.id) ? "hidden" : "visible"
                let minimized = window.isMinimized ? "minimized" : "normal"
                let title = window.title.isEmpty ? "(untitled)" : window.title
                let frame = window.frame.map(formatFrame) ?? "frame=?"
                lines.append("\(marker) id=\(window.id) ws=\(workspace) \(hidden) \(minimized) pid=\(window.app.pid) \(window.app.name) :: \(title) \(frame)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatFrame(_ frame: WindowFrame) -> String {
        "x=\(format(frame.origin.x)) y=\(format(frame.origin.y)) w=\(format(frame.size.width)) h=\(format(frame.size.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }

    @objc private func refreshButtonClicked() {
        refresh()
    }

    @objc private func closeButtonClicked() {
        close()
    }
}
