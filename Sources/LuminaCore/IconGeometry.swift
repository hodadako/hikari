import Foundation
import CoreGraphics

/// Geometry shared by every runtime app-icon renderer.
///
/// A custom icon is rendered with an aspect-fill crop into a square canvas.
/// Keeping that calculation in the core target prevents the menu-bar icon and
/// the settings/About previews from choosing different crops and exposing
/// transparent margins that look like a broken border.
public enum IconGeometry {
    public static let canvasSize = CGSize(width: 1024, height: 1024)
    public static let canvasBounds = CGRect(origin: .zero, size: canvasSize)

    /// Apple system icons leave a small transparent margin around the visible
    /// rounded square. Keep Lumina's built-in and custom icons at the same
    /// visual scale instead of filling the entire 1024px canvas.
    public static let iconInset: CGFloat = 72
    public static let iconFrame = canvasBounds.insetBy(dx: iconInset, dy: iconInset)
    public static let cornerRadius = iconFrame.width * 0.22

    /// Returns the centered source rectangle that fills `targetSize` without
    /// stretching. The returned rectangle is always contained in
    /// `sourceSize`; callers draw this rectangle into the full target canvas.
    public static func aspectFillSourceRect(
        sourceSize: CGSize,
        targetSize: CGSize
    ) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return .zero
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let targetAspect = targetSize.width / targetSize.height

        if sourceAspect > targetAspect {
            let croppedWidth = sourceSize.height * targetAspect
            return CGRect(
                x: (sourceSize.width - croppedWidth) / 2,
                y: 0,
                width: croppedWidth,
                height: sourceSize.height
            )
        }

        let croppedHeight = sourceSize.width / targetAspect
        return CGRect(
            x: 0,
            y: (sourceSize.height - croppedHeight) / 2,
            width: sourceSize.width,
            height: croppedHeight
        )
    }
}

/// Geometry for images displayed in the macOS menu bar.
///
/// Menu bar artwork comes from different sources and therefore has different
/// transparent margins. Normalize its visible pixels into one smaller frame so
/// every preset and custom icon has the same visual size in the status item.
public enum MenuBarIconGeometry {
    /// The status item renders at 18pt and the settings preview at 58pt.
    /// A 256px bitmap leaves ample Retina headroom for both while avoiding
    /// persistent 1024px RGBA backing stores for menu-bar-only artwork.
    public static let canvasSize = CGSize(width: 256, height: 256)
    public static let canvasBounds = CGRect(origin: .zero, size: canvasSize)
    /// Keep the existing 6.25% visual margin when reducing the canvas.
    public static let iconInset: CGFloat = 16
    public static let iconFrame = canvasBounds.insetBy(dx: iconInset, dy: iconInset)
}
