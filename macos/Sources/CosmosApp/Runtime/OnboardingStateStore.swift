import Foundation

final class OnboardingStateStore {
    static let currentVersion = 1

    private enum Key {
        static let completedVersion = "onboarding.completedVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var requiresOnboarding: Bool {
        defaults.integer(forKey: Key.completedVersion) < Self.currentVersion
    }

    func markCompleted() {
        defaults.set(Self.currentVersion, forKey: Key.completedVersion)
    }

    func reset() -> Int {
        let completedVersion = defaults.integer(forKey: Key.completedVersion)
        defaults.removeObject(forKey: Key.completedVersion)
        return completedVersion
    }

    func restoreCompletedVersion(_ completedVersion: Int) {
        if completedVersion == 0 {
            defaults.removeObject(forKey: Key.completedVersion)
        } else {
            defaults.set(completedVersion, forKey: Key.completedVersion)
        }
    }
}
