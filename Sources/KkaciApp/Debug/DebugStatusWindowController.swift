import AppKit
import KkaciCore

final class DebugStatusWindowController: NSWindowController {
    private let renderer: DebugStatusRenderer
    private let textView = NSTextView()

    init(controller: WorkspaceController) {
        renderer = DebugStatusRenderer(controller: controller)

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

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        textView.string = renderer.render()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        configureTextView()
        let scrollView = makeScrollView()
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
            closeButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor)
        ])
    }

    private func configureTextView() {
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
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        return scrollView
    }

    @objc private func refreshButtonClicked() {
        refresh()
    }

    @objc private func closeButtonClicked() {
        close()
    }
}
