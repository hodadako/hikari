struct AppVariant {
    let displayName: String
    let applicationSupportDirectoryName: String
    let supportsScreenSaver: Bool
    let supportsAutomaticUpdates: Bool
    let isNativeLocal: Bool

    static let current: AppVariant = {
        #if LUMINA_NATIVE_LOCAL
        AppVariant(
            displayName: "Hikari",
            applicationSupportDirectoryName: "LuminaNative",
            supportsScreenSaver: false,
            supportsAutomaticUpdates: false,
            isNativeLocal: true
        )
        #else
        AppVariant(
            displayName: "Lumina",
            applicationSupportDirectoryName: "Lumina",
            supportsScreenSaver: true,
            supportsAutomaticUpdates: true,
            isNativeLocal: false
        )
        #endif
    }()
}
