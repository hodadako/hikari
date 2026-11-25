import AppKit
import HikariCore
import SwiftUI

extension AppIconStyle {
    var assetName: String? {
        switch self {
        case .hikari: "HikariIconDefault"
        case .custom: nil
        }
    }

    var localizedName: String {
        switch self {
        case .hikari: NSLocalizedString("Hikari", comment: "Default Hikari app icon")
        case .custom: NSLocalizedString("Custom", comment: "Custom app icon")
        }
    }
}

extension MenuBarIconStyle {
    var assetName: String? {
        switch self {
        case .hikari: "MenuBarIconHikari"
        case .custom: nil
        }
    }

    var isTemplate: Bool {
        false
    }

    var localizedName: String {
        switch self {
        case .hikari: NSLocalizedString("Hikari", comment: "Default Hikari menu bar icon")
        case .custom: NSLocalizedString("Custom", comment: "Custom menu bar icon")
        }
    }
}

struct HikariIconPreview: View {
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

struct MenuBarIconArtwork: View {
    let image: NSImage
    let size: CGFloat
    let style: MenuBarIconStyle
    let isPlaying: Bool

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .renderingMode(style.isTemplate ? .template : .original)
            .foregroundStyle(.primary)
            .scaledToFit()
            .frame(width: size, height: size)
            .overlay {
                if style == .hikari && isPlaying {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 5.5 / 18, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .offset(y: -size * 2 / 18)
                }
            }
    }
}

struct MenuBarIconPreview: View {
    let image: NSImage?
    let size: CGFloat
    let style: MenuBarIconStyle

    var body: some View {
        Group {
            if let image {
                MenuBarIconArtwork(image: image, size: size, style: style, isPlaying: true)
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
