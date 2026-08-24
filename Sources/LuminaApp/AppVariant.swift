struct AppVariant {
    let displayName = "Hikari"
    /// The original Lumina directory is the canonical user library. Hikari
    /// migrates the former LuminaNative directory into it once at launch.
    let applicationSupportDirectoryName = "Lumina"
    let supportsAutomaticUpdates = true

    static let current = AppVariant()
}
