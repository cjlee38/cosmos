import AppKit
import Carbon
import CosmosCore

final class ShortcutRecorderButton: NSButton {
    let shortcutTarget: ShortcutTarget
    private(set) var currentShortcut: String?
    var onValidationMessageChanged: ((String?) -> Void)?
    private var eventMonitor: Any?
    private var onCommit: ((String?) throws -> Bool)?
    private var onCancel: (() throws -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var persistedValidationMessage: String?
    private(set) var isRecording = false

    init(
        shortcutTarget: ShortcutTarget,
        shortcut: String?,
        validationMessage: String? = nil
    ) {
        self.shortcutTarget = shortcutTarget
        currentShortcut = shortcut
        persistedValidationMessage = validationMessage
        super.init(frame: .zero)
        title = ShortcutDisplayFormatter.format(shortcut)
        font = .systemFont(ofSize: 12, weight: .medium)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        controlSize = .large
        focusRingType = .exterior
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyValidationAppearance(validationMessage)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var needsPanelToBecomeKey: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    @discardableResult
    func startRecording(
        onCommit: @escaping (String?) throws -> Bool,
        onCancel: @escaping () throws -> Void,
        onFinish: @escaping (Bool) -> Void
    ) -> Bool {
        guard !isRecording else {
            return false
        }

        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onFinish = onFinish
        isRecording = true
        showRecordingTitle()
        applyValidationAppearance(nil)
        toolTip = "Press Escape to cancel or Delete to clear"
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isRecording else {
                return event
            }
            handle(event)
            return nil
        }
        window?.makeFirstResponder(self)
        return true
    }

    @discardableResult
    func cancelRecording() -> Bool {
        guard isRecording else {
            return true
        }
        do {
            try onCancel?()
        } catch {
            NSSound.beep()
            return false
        }
        finishRecording(
            shortcut: currentShortcut,
            validationMessage: persistedValidationMessage,
            didPersistChange: false
        )
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording, !cancelRecording() {
            return false
        }
        return super.resignFirstResponder()
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else {
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancelRecording()
        case kVK_Delete, kVK_ForwardDelete:
            commit(nil)
        default:
            guard let shortcut = KeyboardShortcutKeyCodec.shortcutString(for: event) else {
                NSSound.beep()
                return
            }
            commit(shortcut)
        }
    }

    private func commit(_ shortcut: String?) {
        do {
            guard try onCommit?(shortcut) == true else {
                finishRecording(
                    shortcut: currentShortcut,
                    validationMessage: persistedValidationMessage,
                    didPersistChange: false
                )
                return
            }
            currentShortcut = shortcut
            persistedValidationMessage = nil
            finishRecording(shortcut: shortcut, validationMessage: nil, didPersistChange: true)
        } catch {
            do {
                try onCancel?()
            } catch {
                NSSound.beep()
                return
            }
            finishRecording(
                shortcut: currentShortcut,
                validationMessage: persistedValidationMessage,
                didPersistChange: false
            )
            NSSound.beep()
        }
    }

    private func finishRecording(
        shortcut: String?,
        validationMessage: String?,
        didPersistChange: Bool
    ) {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        title = ShortcutDisplayFormatter.format(shortcut)
        applyValidationAppearance(validationMessage)
        onCommit = nil
        onCancel = nil
        let finish = onFinish
        onFinish = nil
        finish?(didPersistChange)
    }

    private func applyValidationAppearance(_ message: String?) {
        toolTip = message
        onValidationMessageChanged?(message)
    }

    private func showRecordingTitle() {
        let title = NSMutableAttributedString(
            string: "●",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.systemRed
            ]
        )
        title.append(
            NSAttributedString(
                string: "  REC",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.systemRed
                ]
            )
        )
        attributedTitle = title
    }
}

final class ShortcutRecordingController {
    private let log = Log(category: "settings")
    private let service: any SpaceSettingsServing
    private var activeRecorder: ShortcutRecorderButton?

    init(service: any SpaceSettingsServing) {
        self.service = service
    }

    @discardableResult
    func cancel() -> Bool {
        activeRecorder?.cancelRecording() ?? true
    }

    func begin(_ recorder: ShortcutRecorderButton) {
        guard activeRecorder?.cancelRecording() != false else {
            return
        }
        do {
            try service.beginShortcutRecording()
        } catch {
            log.error("Shortcut recording failed to start: \(String(describing: error))")
            NSSound.beep()
            return
        }

        activeRecorder = recorder
        let shortcutTarget = recorder.shortcutTarget
        recorder.startRecording(
            onCommit: { [unowned self] shortcut in
                do {
                    return try service.updateShortcut(shortcut, for: shortcutTarget)
                } catch {
                    log.error("Shortcut update failed: \(String(describing: error))")
                    throw error
                }
            },
            onCancel: { [unowned self] in
                do {
                    try service.cancelShortcutRecording()
                } catch {
                    log.error("Shortcut recording cancel failed: \(String(describing: error))")
                    throw error
                }
            },
            onFinish: { [weak self, weak recorder] didPersistChange in
                guard self?.activeRecorder === recorder else {
                    return
                }
                self?.activeRecorder = nil
                self?.service.shortcutRecordingDidFinish(didPersistChange: didPersistChange)
            }
        )
    }
}

final class ShortcutRecorderControl: NSStackView {
    let recorderButton: ShortcutRecorderButton
    let warningIcon = NSImageView()
    private var validationMessage: String?

    init(recorderButton: ShortcutRecorderButton, validationMessage: String?) {
        self.recorderButton = recorderButton
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 5

        warningIcon.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: "Shortcut conflict"
        )
        warningIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        warningIcon.contentTintColor = .systemRed
        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        warningIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        warningIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        addArrangedSubview(recorderButton)
        addArrangedSubview(warningIcon)

        recorderButton.onValidationMessageChanged = { [weak self] message in
            self?.applyValidationMessage(message)
        }
        applyValidationMessage(validationMessage)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyToolTip()
    }

    private func applyValidationMessage(_ message: String?) {
        validationMessage = message
        warningIcon.alphaValue = message == nil ? 0 : 1
        applyToolTip()
    }

    private func applyToolTip() {
        recorderButton.toolTip = validationMessage
        warningIcon.toolTip = validationMessage
    }
}
