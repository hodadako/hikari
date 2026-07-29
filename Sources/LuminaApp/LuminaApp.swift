import AppKit
import SwiftUI

@main
struct LuminaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label("Lumina", systemImage: "sparkles.tv")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 560, minHeight: 460)
        }
    }
}
