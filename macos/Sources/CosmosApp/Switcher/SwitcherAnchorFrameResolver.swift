import CosmosCore

enum SwitcherAnchorFrameResolver {
    static func resolve(
        windows: [WindowSnapshot],
        preferredWindowID: WindowID?,
        currentSpace: String,
        membership: (WindowID) -> String?,
        isHidden: (WindowID) -> Bool
    ) -> WindowFrame? {
        if let preferredWindowID,
           let preferredFrame = windows.first(where: { $0.id == preferredWindowID })?.frame {
            return preferredFrame
        }

        return windows.first {
            membership($0.id) == currentSpace
                && !isHidden($0.id)
                && !$0.isMinimized
                && $0.frame != nil
        }?.frame
    }
}
