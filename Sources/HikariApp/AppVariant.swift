struct AppVariant {
    let displayName = "Hikari"
    /// Hikari owns the canonical user library. Data from either predecessor
    /// support directory is merged into it once at launch.
    let applicationSupportDirectoryName = "Hikari"
    let supportsAutomaticUpdates = true

    static let current = AppVariant()
}
