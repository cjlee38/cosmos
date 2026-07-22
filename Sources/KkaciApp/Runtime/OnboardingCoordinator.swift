import AppKit

final class OnboardingCoordinator {
    private let stateStore: OnboardingStateStore
    private let windowController: OnboardingWindowController
    private let onComplete: () -> Void

    init(
        stateStore: OnboardingStateStore,
        generalSettingsService: GeneralSettingsService,
        workspaceSettingsService: any WorkspaceSettingsServing,
        shortcutRecordingController: ShortcutRecordingController,
        onComplete: @escaping () -> Void
    ) {
        self.stateStore = stateStore
        self.onComplete = onComplete

        var completeHandler: () -> Void = {}
        let permissionViewController = OnboardingPermissionViewController(
            service: generalSettingsService
        )
        let workspaceViewController = WorkspaceSettingsViewController(
            service: workspaceSettingsService,
            shortcutRecordingController: shortcutRecordingController
        )
        let contentViewController = OnboardingViewController(
            permissionViewController: permissionViewController,
            workspaceViewController: workspaceViewController,
            canComplete: { workspaceSettingsService.snapshot().isEditable },
            onComplete: { completeHandler() }
        )
        windowController = OnboardingWindowController(contentViewController: contentViewController)
        completeHandler = { [weak self] in
            self?.complete()
        }
    }

    func show() {
        windowController.show()
    }

    func refresh() {
        windowController.refresh()
    }

    private func complete() {
        stateStore.markCompleted()
        windowController.dismiss()
        onComplete()
    }
}

private final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onboardingViewController: OnboardingViewController
    private var activationObserver: NSObjectProtocol?

    init(contentViewController: OnboardingViewController) {
        onboardingViewController = contentViewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Kkaci"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 820, height: 620)
        window.setAccessibilityIdentifier("kkaci.onboarding")
        window.contentViewController = contentViewController

        super.init(window: window)
        window.delegate = self
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func show() {
        refresh()
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        onboardingViewController.refresh()
    }

    func dismiss() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_: Notification) {
        refresh()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}

final class OnboardingViewController: NSViewController {
    private enum Step {
        case permissions
        case workspaces
    }

    private let permissionViewController: OnboardingPermissionViewController
    private let workspaceViewController: WorkspaceSettingsViewController
    private let canComplete: () -> Bool
    private let onComplete: () -> Void
    private let permissionsStepLabel = NSTextField(labelWithString: "1  Permissions")
    private let workspacesStepLabel = NSTextField(labelWithString: "2  Workspaces")
    private let contentContainer = NSView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)
    private var currentViewController: NSViewController?
    private var step = Step.permissions

    init(
        permissionViewController: OnboardingPermissionViewController,
        workspaceViewController: WorkspaceSettingsViewController,
        canComplete: @escaping () -> Bool,
        onComplete: @escaping () -> Void
    ) {
        self.permissionViewController = permissionViewController
        self.workspaceViewController = workspaceViewController
        self.canComplete = canComplete
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 680))
        configureStepLabel(permissionsStepLabel)
        configureStepLabel(workspacesStepLabel)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        configureNavigationButtons()

        let header = makeHeader()
        let footer = makeFooter()
        let root = makeRootView(header: header, footer: footer)
        view.addSubview(root)
        constrainRoot(root, header: header, footer: footer)
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        show(permissionViewController)
        refresh()
    }

    private func configureNavigationButtons() {
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        backButton.controlSize = .large
        backButton.setAccessibilityIdentifier("kkaci.onboarding.back")
        continueButton.target = self
        continueButton.action = #selector(continueSetup)
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.keyEquivalent = "\r"
        continueButton.setAccessibilityIdentifier("kkaci.onboarding.continue")
    }

    private func makeHeader() -> NSStackView {
        let title = NSTextField(labelWithString: "Set Up Kkaci")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let steps = NSStackView(views: [
            permissionsStepLabel,
            separatorArrow(),
            workspacesStepLabel
        ])
        steps.orientation = .horizontal
        steps.alignment = .centerY
        steps.spacing = 10
        let header = NSStackView(views: [title, SettingsControlFactory.flexibleSpacer(), steps])
        header.orientation = .horizontal
        header.alignment = .centerY
        return header
    }

    private func makeFooter() -> NSStackView {
        let actions = NSStackView(views: [
            SettingsControlFactory.flexibleSpacer(),
            backButton,
            continueButton
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        let footer = NSStackView(views: [SettingsControlFactory.separator(), actions])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 12
        for child in footer.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        }
        return footer
    }

    private func makeRootView(header: NSView, footer: NSView) -> NSStackView {
        let root = NSStackView(views: [header, contentContainer, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        return root
    }

    private func constrainRoot(_ root: NSView, header: NSView, footer: NSView) {
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }
        permissionViewController.refresh()
        workspaceViewController.refresh()
        updateNavigation()
    }

    private func show(_ viewController: NSViewController) {
        if let currentViewController {
            currentViewController.view.removeFromSuperview()
            currentViewController.removeFromParent()
        }

        addChild(viewController)
        let contentView = viewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        currentViewController = viewController
    }

    private func updateNavigation() {
        let isPermissionsStep = step == .permissions
        permissionsStepLabel.textColor = isPermissionsStep ? .labelColor : .secondaryLabelColor
        workspacesStepLabel.textColor = isPermissionsStep ? .secondaryLabelColor : .labelColor
        backButton.isHidden = isPermissionsStep
        if isPermissionsStep {
            continueButton.title = permissionViewController.hasScreenRecordingPermission
                ? "Continue"
                : "Continue Without Previews"
            continueButton.isEnabled = permissionViewController.hasAccessibilityPermission
        } else {
            continueButton.title = "Start Kkaci"
            continueButton.isEnabled = canComplete()
        }
    }

    private func configureStepLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
    }

    private func separatorArrow() -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )
        image.contentTintColor = .tertiaryLabelColor
        return image
    }

    @objc private func goBack() {
        step = .permissions
        show(permissionViewController)
        updateNavigation()
    }

    @objc private func continueSetup() {
        switch step {
        case .permissions:
            guard permissionViewController.hasAccessibilityPermission else {
                return
            }
            step = .workspaces
            show(workspaceViewController)
            updateNavigation()
        case .workspaces:
            guard canComplete() else {
                return
            }
            onComplete()
        }
    }
}
