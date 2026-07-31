import AppKit
import SwiftUI

@main
struct LuminaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(model.appIconAssetName)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityLabel("Lumina")
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
