import Foundation

struct SpaceMemberships {
    private var spaceByWindowID: [WindowID: SpaceID] = [:]

    var assignedWindowIDs: [WindowID] {
        Array(spaceByWindowID.keys)
    }

    func space(for id: WindowID) -> SpaceID? {
        spaceByWindowID[id]
    }

    mutating func assign(_ id: WindowID, to space: SpaceID) {
        spaceByWindowID[id] = space
    }

    mutating func remove(_ id: WindowID) {
        spaceByWindowID[id] = nil
    }

    mutating func reassignInvalidSpaces(validSpaces: Set<SpaceID>, to space: SpaceID) {
        for (id, assignedSpace) in spaceByWindowID where !validSpaces.contains(assignedSpace) {
            spaceByWindowID[id] = space
        }
    }

    func windowIDs(in space: SpaceID) -> [WindowID] {
        spaceByWindowID.compactMap { id, assignedSpace in
            assignedSpace == space ? id : nil
        }
    }
}
