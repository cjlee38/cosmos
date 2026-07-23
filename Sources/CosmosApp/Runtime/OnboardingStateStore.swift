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
}
