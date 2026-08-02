import AppKit
import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model)
        } label: {
            MenuBarIconView(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIconView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        LuminaIconPreview(
            image: model.appIconImage,
            size: 18
        )
        .accessibilityLabel("Lumina")
    }
}
