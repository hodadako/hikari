import AppKit
import LuminaCore

enum MenuBarIconRenderer {
    static func normalizedImage(from sourceImage: NSImage) -> NSImage {
        guard let representation = bitmapRepresentation(for: sourceImage) else {
            return sourceImage
        }

        let sourceRect = alphaContentRect(
            for: sourceImage,
            representation: representation
        )
        let destinationRect = aspectFitRect(
            sourceSize: sourceRect.size,
            inside: MenuBarIconGeometry.iconFrame
        )

        guard let normalizedRepresentation = renderedRepresentation(
            sourceImage,
            sourceRect: sourceRect,
            destinationRect: destinationRect
        ) else {
            return sourceImage
        }

        let normalizedImage = NSImage(size: MenuBarIconGeometry.canvasSize)
        normalizedImage.addRepresentation(normalizedRepresentation)
        normalizedImage.isTemplate = sourceImage.isTemplate
        return normalizedImage
    }

    private static func bitmapRepresentation(for image: NSImage) -> NSBitmapImageRep? {
        if let representation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
            return representation
        }
        guard let data = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }

    private static func alphaContentRect(
        for image: NSImage,
        representation: NSBitmapImageRep
    ) -> NSRect {
        let fullRect = NSRect(origin: .zero, size: image.size)
        guard representation.hasAlpha else { return fullRect }

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

        guard maxX >= minX, maxY >= minY else { return fullRect }

        let scaleX = image.size.width / CGFloat(representation.pixelsWide)
        let scaleY = image.size.height / CGFloat(representation.pixelsHigh)
        let inset: CGFloat = 1
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

    private static func aspectFitRect(
        sourceSize: NSSize,
        inside targetRect: NSRect
    ) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return targetRect
        }

        let scale = min(
            targetRect.width / sourceSize.width,
            targetRect.height / sourceSize.height
        )
        let size = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        return NSRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func renderedRepresentation(
        _ image: NSImage,
        sourceRect: NSRect,
        destinationRect: NSRect
    ) -> NSBitmapImageRep? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(MenuBarIconGeometry.canvasSize.width),
            pixelsHigh: Int(MenuBarIconGeometry.canvasSize.height),
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

        let canvas = NSRect(origin: .zero, size: MenuBarIconGeometry.canvasSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(canvas)
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }
}
