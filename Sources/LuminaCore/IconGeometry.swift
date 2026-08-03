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
