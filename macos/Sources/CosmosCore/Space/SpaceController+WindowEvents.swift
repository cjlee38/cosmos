public extension SpaceController {
    func handleWindowSetChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange())
    }

    func handleFocusedWindowChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(focusPolicy: .always))
    }

    func handleWindowLayoutChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(focusPolicy: .visibleFocusedWindow))
    }

    func handleDisplayConfigurationChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(displayConfigurationChanged: true))
    }
}
