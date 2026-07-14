import Foundation

struct HiddenWindowFrameStore {
    private var hiddenFrames: [WindowID: WindowFrame] = [:]

    var hiddenWindowIDs: [WindowID] {
        hiddenFrames.keys.sorted()
    }

    func isHidden(_ id: WindowID) -> Bool {
        hiddenFrames[id] != nil
    }

    func frame(for id: WindowID) -> WindowFrame? {
        hiddenFrames[id]
    }

    mutating func storeIfNeeded(_ frame: WindowFrame, for id: WindowID) {
        if hiddenFrames[id] == nil {
            hiddenFrames[id] = frame
        }
    }

    mutating func replace(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames[id] = frame
    }

    mutating func clear(_ id: WindowID) {
        hiddenFrames[id] = nil
    }
}
