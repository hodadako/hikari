import AppKit
import Foundation
import LuminaCore

enum CustomMenuBarIconError: LocalizedError {
    case unreadableImage
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return NSLocalizedString(
                "The selected menu bar icon could not be read.",
                comment: "Unreadable custom menu bar icon error"
            )
        case .renderingFailed:
            return NSLocalizedString(
                "The custom menu bar icon could not be prepared.",
                comment: "Custom menu bar icon rendering error"
            )
        }
    }
}

final class CustomMenuBarIconStore {
    private let container: SharedContainer
    private var cachedRelativePath: String?
    private var cachedImage: NSImage?

    init(container: SharedContainer) {
        self.container = container
    }

    func importIcon(from sourceURL: URL) throws -> String {
        guard let sourceImage = NSImage(contentsOf: sourceURL),
              sourceImage.size.width > 0,
              sourceImage.size.height > 0 else {
            throw CustomMenuBarIconError.unreadableImage
        }
        guard let representation = renderedRepresentation(sourceImage) else {
            throw CustomMenuBarIconError.renderingFailed
        }
        guard let png = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CustomMenuBarIconError.renderingFailed
        }

        try png.write(to: container.customMenuBarIconURL, options: .atomic)
        cachedRelativePath = container.customMenuBarIconURL.lastPathComponent
        cachedImage = image(from: representation)
        return container.customMenuBarIconURL.lastPathComponent
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
        cachedRelativePath = relativePath
        cachedImage = storedImage
        return storedImage
    }

    private func renderedRepresentation(_ image: NSImage) -> NSBitmapImageRep? {
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
        let sourceRect = IconGeometry.aspectFillSourceRect(
            sourceSize: image.size,
            targetSize: canvas.size
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(canvas)
        image.draw(
            in: canvas,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private func image(from representation: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: IconGeometry.canvasSize)
        image.addRepresentation(representation)
        return image
    }
}
