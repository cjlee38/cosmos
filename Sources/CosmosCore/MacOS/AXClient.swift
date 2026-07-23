import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PrivateApi

final class WindowHandle {
    let id: WindowID
    let app: RunningAppInfo
    let runningApp: NSRunningApplication
    let axWindow: AXUIElement

    init(id: WindowID, app: RunningAppInfo, runningApp: NSRunningApplication, axWindow: AXUIElement) {
        self.id = id
        self.app = app
        self.runningApp = runningApp
        self.axWindow = axWindow
    }
}

enum AXClientError: Error, CustomStringConvertible {
    case accessibilityPermissionMissing
    case attributeUnavailable(String)
    case readAttributeFailed(String, AXError)
    case setAttributeFailed(String, AXError)

    var description: String {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is not granted."
        case let .attributeUnavailable(name):
            "AX attribute is unavailable: \(name)"
        case let .readAttributeFailed(name, error):
            "Failed to read AX attribute \(name): \(error)"
        case let .setAttributeFailed(name, error):
            "Failed to set AX attribute \(name): \(error)"
        }
    }
}

public final class AXClient {
    private let includedOwnWindowIdentifiers: Set<String>

    public init(includedOwnWindowIdentifiers: Set<String> = []) {
        self.includedOwnWindowIdentifiers = includedOwnWindowIdentifiers
    }

    public static func windowID(for element: AXUIElement) -> WindowID? {
        element.containingWindowID()
    }

    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func enumerateWindows() throws -> [WindowHandle] {
        var result: [WindowHandle] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let handles = try enumerateWindows(for: app)
            if app.processIdentifier == getpid() {
                result.append(contentsOf: handles.filter(isIncludedOwnWindow))
            } else {
                result.append(contentsOf: handles)
            }
        }
        return result
    }

    func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(kAXFocusedWindowAttribute, from: axApp) else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let focusedWindow = focused as! AXUIElement
        if app.processIdentifier == getpid(), !isIncludedOwnWindow(focusedWindow) {
            return nil
        }
        return focusedWindow.containingWindowID()
    }

    func snapshot(for handle: WindowHandle) -> WindowSnapshot {
        WindowSnapshot(
            id: handle.id,
            app: handle.app,
            title: stringAttribute(kAXTitleAttribute, from: handle.axWindow) ?? "",
            frame: frame(for: handle.axWindow),
            isMinimized: boolAttribute(kAXMinimizedAttribute, from: handle.axWindow) ?? false
        )
    }

    func frame(for window: AXUIElement) -> WindowFrame? {
        guard let origin = pointAttribute(kAXPositionAttribute, from: window),
              let size = sizeAttribute(kAXSizeAttribute, from: window)
        else {
            return nil
        }
        return WindowFrame(origin: origin, size: size)
    }

    func setPosition(_ point: CGPoint, for window: AXUIElement) throws {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw AXClientError.attributeUnavailable(kAXPositionAttribute)
        }

        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard error == .success else {
            throw AXClientError.setAttributeFailed(kAXPositionAttribute, error)
        }
    }

    func setFrame(_ frame: WindowFrame, for window: AXUIElement) throws {
        // AX has no atomic frame setter. Resize before and after the move so
        // cross-display transfers work whether the target display is smaller or larger.
        try setSize(frame.size, for: window)
        try setPosition(frame.origin, for: window)
        try setSize(frame.size, for: window)
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) throws {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            throw AXClientError.attributeUnavailable(kAXSizeAttribute)
        }

        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        guard error == .success else {
            throw AXClientError.setAttributeFailed(kAXSizeAttribute, error)
        }
    }

    func focus(_ handle: WindowHandle) {
        AXUIElementSetAttributeValue(handle.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(handle.axWindow, kAXRaiseAction as CFString)
        handle.runningApp.activate(options: [.activateIgnoringOtherApps])
    }

    private func enumerateWindows(for app: NSRunningApplication) throws -> [WindowHandle] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let rawWindows = try windowsAttribute(from: axApp)

        let appInfo = RunningAppInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "unknown"
        )

        return rawWindows.compactMap { rawWindow in
            // swiftlint:disable:next force_cast
            let axWindow = rawWindow as! AXUIElement
            guard isManageableWindow(axWindow),
                  let id = axWindow.containingWindowID()
            else {
                return nil
            }
            return WindowHandle(id: id, app: appInfo, runningApp: app, axWindow: axWindow)
        }
    }

    private func windowsAttribute(from app: AXUIElement) throws -> NSArray {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        switch error {
        case .success:
            guard let windows = value as? NSArray else {
                throw AXClientError.attributeUnavailable(kAXWindowsAttribute)
            }
            return windows
        default:
            throw AXClientError.readAttributeFailed(kAXWindowsAttribute, error)
        }
    }

    private func isManageableWindow(_ window: AXUIElement) -> Bool {
        stringAttribute(kAXRoleAttribute, from: window) == kAXWindowRole as String
            && frame(for: window) != nil
    }

    private func isIncludedOwnWindow(_ handle: WindowHandle) -> Bool {
        isIncludedOwnWindow(handle.axWindow)
    }

    private func isIncludedOwnWindow(_ window: AXUIElement) -> Bool {
        guard let identifier = stringAttribute(kAXIdentifierAttribute, from: window) else {
            return false
        }
        return includedOwnWindowIdentifiers.contains(identifier)
    }

    private func copyAttribute(_ name: String, from element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? value : nil
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        copyAttribute(name, from: element) as? String
    }

    private func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
        copyAttribute(name, from: element) as? Bool
    }

    private func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
        guard let value = copyAttribute(name, from: element) else {
            return nil
        }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        let axValue = value as! AXValue
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
        guard let value = copyAttribute(name, from: element) else {
            return nil
        }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        let axValue = value as! AXValue
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}

private extension AXUIElement {
    func containingWindowID() -> WindowID? {
        var id = WindowID()
        return _AXUIElementGetWindow(self, &id) == .success ? id : nil
    }
}
