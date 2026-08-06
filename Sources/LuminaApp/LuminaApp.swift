import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model)
        } label: {
            MenuBarIconView(model: appDelegate.model)
                .accessibilityLabel("Lumina")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIconView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: model.menuBarIconImage)
            .resizable()
            .interpolation(.high)
            .renderingMode(
                model.menuBarIconIsTemplate ? .template : .original
            )
            .foregroundStyle(.primary)
            .scaledToFit()
            .frame(width: 18, height: 18)
    }
}
