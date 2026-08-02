import AppKit
import LuminaCore
import SwiftUI

extension AppIconStyle {
    var assetName: String? {
        switch self {
        case .blue: "LuminaIconBlue"
        case .pink: "LuminaIconPink"
        case .purple: "LuminaIconPurple"
        case .custom: nil
        }
    }

    var localizedName: String {
        switch self {
        case .blue: NSLocalizedString("Blue", comment: "Blue app icon")
        case .pink: NSLocalizedString("Pink", comment: "Pink app icon")
        case .purple: NSLocalizedString("Purple", comment: "Purple app icon")
        case .custom: NSLocalizedString("Custom", comment: "Custom app icon")
        }
    }
}

struct LuminaIconPreview: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.3, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: size * 0.22,
                style: .continuous
            )
        )
    }
}
