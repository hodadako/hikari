import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model)
        } label: {
            // Menu bar labels should use a monochrome SF Symbol. The selected
            // application icon is intentionally kept out of this small
            // template image slot because its artwork can render oversized.
            Image(systemName: "sparkles.tv")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 15, weight: .medium))
                .accessibilityLabel("Lumina")
        }
        .menuBarExtraStyle(.window)
    }
}
