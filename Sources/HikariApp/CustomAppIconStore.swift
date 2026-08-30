import AppKit
import Foundation
import HikariCore

enum CustomAppIconError: LocalizedError {
    case unreadableImage
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return NSLocalizedString(
                "The selected custom icon could not be read.",
                comment: "Unreadable custom app icon error"
            )
        case .renderingFailed:
            return NSLocalizedString(
                "The custom icon could not be prepared.",
                comment: "Custom app icon rendering error"
            )
        }
    }
}

final class CustomAppIconStore {
    private let container: SharedContainer
    private var cachedRelativePath: String?
    private var cachedImage: NSImage?

    init(container: SharedContainer) {
        self.container = container
    }

    func importIcon(from sourceURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: sourceURL),
              image.size.width > 0,
              image.size.height > 0 else {
            throw CustomAppIconError.unreadableImage
        }
        let canvas = NSRect(origin: .zero, size: IconGeometry.canvasSize)
        let sourceRect = IconGeometry.aspectFillSourceRect(
            sourceSize: image.size,
            targetSize: canvas.size
        )
        guard let representation = renderedRepresentation(
            image,
            sourceRect: sourceRect
        ) else {
            throw CustomAppIconError.renderingFailed
        }

        guard let png = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CustomAppIconError.renderingFailed
        }
        try png.write(to: container.customAppIconURL, options: .atomic)
        cachedRelativePath = container.customAppIconURL.lastPathComponent
        cachedImage = self.image(from: representation)
        return container.customAppIconURL.lastPathComponent
    }

    func image(relativePath: String?) -> NSImage? {
        guard let relativePath,
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath else {
            return nil
        }
        if cachedRelativePath == relativePath {
            return cachedImage
        }
        guard let storedImage = NSImage(
            contentsOf: container.rootURL.appendingPathComponent(relativePath)
        ) else {
            return nil
        }

        // Older versions used aspect-fit and persisted transparent margins.
        // Crop those margins once on load so an existing custom icon gets the
        // same edge-to-edge treatment as a newly imported icon.
        let contentRect = alphaContentRect(for: storedImage)
        let sourceRect = IconGeometry.aspectFillSourceRect(
            sourceSize: contentRect.size,
            targetSize: IconGeometry.canvasSize
        )
        let absoluteSourceRect = NSRect(
            x: contentRect.minX + sourceRect.minX,
            y: contentRect.minY + sourceRect.minY,
            width: sourceRect.width,
            height: sourceRect.height
        )
        guard let representation = renderedRepresentation(
            storedImage,
            sourceRect: absoluteSourceRect
        ) else {
            return nil
        }
        let normalized = image(from: representation)
        cachedRelativePath = relativePath
        cachedImage = normalized
        return normalized
    }

    private func renderedRepresentation(
        _ image: NSImage,
        sourceRect: NSRect
    ) -> NSBitmapImageRep? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(IconGeometry.canvasSize.width),
            pixelsHigh: Int(IconGeometry.canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        let canvas = NSRect(origin: .zero, size: IconGeometry.canvasSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(canvas)
        let roundedPath = CGPath(
            roundedRect: IconGeometry.iconFrame,
            cornerWidth: IconGeometry.cornerRadius,
            cornerHeight: IconGeometry.cornerRadius,
            transform: nil
        )
        context.cgContext.saveGState()
        context.cgContext.addPath(roundedPath)
        context.cgContext.clip()
        image.draw(
            in: IconGeometry.iconFrame,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )
        context.cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private func image(from representation: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: IconGeometry.canvasSize)
        image.addRepresentation(representation)
        return image
    }

    private func alphaContentRect(for image: NSImage) -> NSRect {
        let fullRect = NSRect(origin: .zero, size: image.size)
        guard let representation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .first,
            representation.hasAlpha else {
            return fullRect
        }

        var minX = representation.pixelsWide
        var minY = representation.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y),
                      color.alphaComponent > 0.02 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return fullRect
        }

        let scaleX = image.size.width / CGFloat(representation.pixelsWide)
        let scaleY = image.size.height / CGFloat(representation.pixelsHigh)
        let inset = 1.0
        let contentWidth = min(
            CGFloat(representation.pixelsWide),
            CGFloat(maxX - minX + 1) + inset * 2
        )
        let contentHeight = min(
            CGFloat(representation.pixelsHigh),
            CGFloat(maxY - minY + 1) + inset * 2
        )
        return NSRect(
            x: max(0, CGFloat(minX) - inset) * scaleX,
            y: max(0, CGFloat(minY) - inset) * scaleY,
            width: contentWidth * scaleX,
            height: contentHeight * scaleY
        )
    }
}
