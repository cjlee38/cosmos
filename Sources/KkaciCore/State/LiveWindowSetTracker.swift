import Foundation

struct LiveWindowSetTracker {
    private var didLoadInitialWindowSet = false
    private var knownWindowIDs: Set<WindowID> = []

    mutating func sync(aliveWindowIDs: Set<WindowID>) -> (new: [WindowID], removed: [WindowID]) {
        if !didLoadInitialWindowSet {
            didLoadInitialWindowSet = true
            knownWindowIDs = aliveWindowIDs
            return (new: [], removed: [])
        }

        let newIDs = aliveWindowIDs.subtracting(knownWindowIDs).sorted()
        let removedIDs = knownWindowIDs.subtracting(aliveWindowIDs).sorted()
        knownWindowIDs = aliveWindowIDs
        return (new: newIDs, removed: removedIDs)
    }

    mutating func recordKnown(_ ids: [WindowID]) {
        for id in ids {
            knownWindowIDs.insert(id)
        }
    }
}
