import Foundation

final class AppSettingsStore {
    private enum Key {
        static let menuBarIconStyle = "appearance.menuBarIconStyle"
        static let windowSwitcherSize = "appearance.windowSwitcherSize"
        static let spaceSwitcherSize = "appearance.spaceSwitcherSize"
    }

    private enum ObsoleteKey {
        static let windowSwitcherItemSize = "appearance.windowSwitcherItemSize"
        static let spaceSwitcherItemSize = "appearance.spaceSwitcherItemSize"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: ObsoleteKey.windowSwitcherItemSize)
        defaults.removeObject(forKey: ObsoleteKey.spaceSwitcherItemSize)
    }

    func snapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            menuBarIconStyle: menuBarIconStyle,
            windowSwitcherSize: windowSwitcherSize,
            spaceSwitcherSize: spaceSwitcherSize
        )
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        defaults.set(style.rawValue, forKey: Key.menuBarIconStyle)
    }

    func setWindowSwitcherSize(_ size: Double) {
        defaults.set(clamp(size, to: SwitcherSizeRange.window), forKey: Key.windowSwitcherSize)
    }

    func setSpaceSwitcherSize(_ size: Double) {
        defaults.set(clamp(size, to: SwitcherSizeRange.space), forKey: Key.spaceSwitcherSize)
    }

    private var menuBarIconStyle: MenuBarIconStyle {
        storedValue(forKey: Key.menuBarIconStyle) ?? .angleBrackets
    }

    private var windowSwitcherSize: Double {
        storedSize(
            forKey: Key.windowSwitcherSize,
            range: SwitcherSizeRange.window,
            defaultValue: SwitcherSizeRange.defaultWindow
        )
    }

    private var spaceSwitcherSize: Double {
        storedSize(
            forKey: Key.spaceSwitcherSize,
            range: SwitcherSizeRange.space,
            defaultValue: SwitcherSizeRange.defaultSpace
        )
    }

    private func storedValue<Value: RawRepresentable>(forKey key: String) -> Value?
        where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    private func storedSize(
        forKey key: String,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) -> Double {
        if defaults.object(forKey: key) != nil {
            return clamp(defaults.double(forKey: key), to: range)
        }
        return defaultValue
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
