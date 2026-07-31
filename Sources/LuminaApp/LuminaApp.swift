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
                .onAppear {
                    DispatchQueue.main.async {
                        SettingsWindowPresenter.shared
                            .showInitialSetupIfNeeded(model: model)
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
