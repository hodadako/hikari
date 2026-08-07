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

extension MenuBarIconStyle {
    var assetName: String? {
        switch self {
        case .empty: "MenuBarIconEmpty"
        case .outlinePurple: "MenuBarIconOutlinePurple"
        case .outlinePink: "MenuBarIconOutlinePink"
        case .outlineBlue: "MenuBarIconOutlineBlue"
        case .outlineViolet: "MenuBarIconOutlineViolet"
        case .filledPurple: "MenuBarIconFilledPurple"
        case .filledPink: "MenuBarIconFilledPink"
        case .filledBlue: "MenuBarIconFilledBlue"
        case .filledViolet: "MenuBarIconFilledViolet"
        case .custom: nil
        }
    }

    var isTemplate: Bool {
        self == .empty
    }

    var localizedName: String {
        switch self {
        case .empty: NSLocalizedString("Default", comment: "Default menu bar icon")
        case .outlinePurple: NSLocalizedString("Purple Outline", comment: "Purple outline menu bar icon")
        case .outlinePink: NSLocalizedString("Pink Outline", comment: "Pink outline menu bar icon")
        case .outlineBlue: NSLocalizedString("Blue Outline", comment: "Blue outline menu bar icon")
        case .outlineViolet: NSLocalizedString("Violet Outline", comment: "Violet outline menu bar icon")
        case .filledPurple: NSLocalizedString("Purple Glow", comment: "Purple filled menu bar icon")
        case .filledPink: NSLocalizedString("Pink Glow", comment: "Pink filled menu bar icon")
        case .filledBlue: NSLocalizedString("Blue Glow", comment: "Blue filled menu bar icon")
        case .filledViolet: NSLocalizedString("Violet Glow", comment: "Violet filled menu bar icon")
        case .custom: NSLocalizedString("Custom", comment: "Custom menu bar icon")
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
                    // Every icon is normalized to a square canvas. Fill here
                    // as a final guard for legacy/custom files so no
                    // transparent side margins become a visible seam.
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
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
        .compositingGroup()
        .clipShape(
            RoundedRectangle(
                cornerRadius: size * 0.22,
                style: .continuous
            )
        )
    }
}

struct MenuBarIconPreview: View {
    let image: NSImage?
    let size: CGFloat
    let isTemplate: Bool

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(isTemplate ? .template : .original)
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.2))
    }
}
