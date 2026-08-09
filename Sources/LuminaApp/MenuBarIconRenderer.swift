import AppKit
import LuminaCore

enum MenuBarIconRenderer {
    static func normalizedImage(
        from sourceImage: NSImage,
        framedBy framingImage: NSImage? = nil
    ) -> NSImage {
        let framingImage = framingImage ?? sourceImage
        guard let representation = bitmapRepresentation(for: framingImage) else {
            return sourceImage
        }

        let framingRect = alphaContentRect(
            for: framingImage,
            representation: representation
        )
        let sourceRect = proportionalRect(
            framingRect,
            from: framingImage.size,
            to: sourceImage.size
        )
        let destinationRect = aspectFitRect(
            sourceSize: framingRect.size,
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
        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1
        let padding = max(
            2,
            Int(ceil(CGFloat(max(contentWidth, contentHeight)) * 0.08))
        )
        let paddedMinX = max(0, minX - padding)
        let paddedMinY = max(0, minY - padding)
        let paddedMaxX = min(representation.pixelsWide - 1, maxX + padding)
        let paddedMaxY = min(representation.pixelsHigh - 1, maxY + padding)

        return NSRect(
            x: CGFloat(paddedMinX) * scaleX,
            y: CGFloat(paddedMinY) * scaleY,
            width: CGFloat(paddedMaxX - paddedMinX + 1) * scaleX,
            height: CGFloat(paddedMaxY - paddedMinY + 1) * scaleY
        )
    }

    private static func proportionalRect(
        _ rect: NSRect,
        from framingSize: NSSize,
        to sourceSize: NSSize
    ) -> NSRect {
        guard framingSize.width > 0, framingSize.height > 0 else {
            return NSRect(origin: .zero, size: sourceSize)
        }
        let scaleX = sourceSize.width / framingSize.width
        let scaleY = sourceSize.height / framingSize.height
        return NSRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
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
