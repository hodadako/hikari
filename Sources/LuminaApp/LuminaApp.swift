import AppKit
import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            LuminaIconPreview(
                image: model.appIconImage,
                size: 18
            )
                .accessibilityLabel("Lumina")
                .onAppear {
                    DispatchQueue.main.async {
                        appDelegate.model = model
                        SettingsWindowPresenter.shared
                            .showOnLaunch(model: model)
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
