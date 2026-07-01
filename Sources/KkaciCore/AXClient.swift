import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PrivateApi

public typealias WindowID = CGWindowID

public struct RunningAppInfo: Equatable {
    public let pid: pid_t
    public let name: String
    public let bundleID: String?

    public init(pid: pid_t, name: String, bundleID: String?) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
    }
}

public struct WindowFrame: Codable, Equatable {
    public var origin: CGPoint
    public var size: CGSize

    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    public var center: CGPoint {
        CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }
}

public struct WindowSnapshot {
    public let id: WindowID
    public let app: RunningAppInfo
    public let title: String
    public let frame: WindowFrame?
    public let isMinimized: Bool

    public init(id: WindowID, app: RunningAppInfo, title: String, frame: WindowFrame?, isMinimized: Bool) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }
}

public final class WindowHandle {
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

public enum AXClientError: Error, CustomStringConvertible {
    case accessibilityPermissionMissing
    case attributeUnavailable(String)
    case setAttributeFailed(String, AXError)

    public var description: String {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is not granted."
        case .attributeUnavailable(let name):
            "AX attribute is unavailable: \(name)"
        case .setAttributeFailed(let name, let error):
            "Failed to set AX attribute \(name): \(error)"
        }
    }
}

public final class AXClient {
    public init() {}

    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func enumerateWindows() -> [WindowHandle] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && app.processIdentifier != getpid()
            }
            .flatMap(enumerateWindows)
    }

    public func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid()
        else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(kAXFocusedWindowAttribute, from: axApp) else {
            return nil
        }
        return manageableWindowID(startingAt: focused as! AXUIElement)
    }

    public func snapshot(for handle: WindowHandle) -> WindowSnapshot {
        WindowSnapshot(
            id: handle.id,
            app: handle.app,
            title: stringAttribute(kAXTitleAttribute, from: handle.axWindow) ?? "",
            frame: frame(for: handle.axWindow),
            isMinimized: boolAttribute(kAXMinimizedAttribute, from: handle.axWindow) ?? false
        )
    }

    public func frame(for window: AXUIElement) -> WindowFrame? {
        guard let origin = pointAttribute(kAXPositionAttribute, from: window),
              let size = sizeAttribute(kAXSizeAttribute, from: window)
        else {
            return nil
        }
        return WindowFrame(origin: origin, size: size)
    }

    public func setPosition(_ point: CGPoint, for window: AXUIElement) throws {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw AXClientError.attributeUnavailable(kAXPositionAttribute)
        }

        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard error == .success else {
            throw AXClientError.setAttributeFailed(kAXPositionAttribute, error)
        }
    }

    public func focus(_ handle: WindowHandle) {
        AXUIElementSetAttributeValue(handle.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(handle.axWindow, kAXRaiseAction as CFString)
        handle.runningApp.activate(options: [.activateIgnoringOtherApps])
    }

    private func enumerateWindows(for app: NSRunningApplication) -> [WindowHandle] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawWindows = copyAttribute(kAXWindowsAttribute, from: axApp) as? NSArray else {
            return []
        }

        let appInfo = RunningAppInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "unknown",
            bundleID: app.bundleIdentifier
        )

        return rawWindows.compactMap { rawWindow in
            let axWindow = rawWindow as! AXUIElement
            guard isManageableWindow(axWindow),
                  let id = axWindow.containingWindowID()
            else {
                return nil
            }
            return WindowHandle(id: id, app: appInfo, runningApp: app, axWindow: axWindow)
        }
    }

    private func manageableWindowID(startingAt element: AXUIElement) -> WindowID? {
        var current = element
        for _ in 0 ..< 8 {
            if isManageableWindow(current),
               let id = current.containingWindowID()
            {
                return id
            }

            guard let parent = copyAttribute(kAXParentAttribute, from: current) else {
                return nil
            }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func isManageableWindow(_ window: AXUIElement) -> Bool {
        stringAttribute(kAXRoleAttribute, from: window) == kAXWindowRole as String
            && frame(for: window) != nil
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
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
        guard let value = copyAttribute(name, from: element) else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}

private extension AXUIElement {
    func containingWindowID() -> WindowID? {
        var id = WindowID()
        return _AXUIElementGetWindow(self, &id) == .success ? id : nil
    }
}
