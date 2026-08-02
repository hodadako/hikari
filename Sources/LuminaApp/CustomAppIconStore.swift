import AppKit
import Foundation
import LuminaCore

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

    init(container: SharedContainer) {
        self.container = container
    }

    func importIcon(from sourceURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: sourceURL),
              image.size.width > 0,
              image.size.height > 0 else {
            throw CustomAppIconError.unreadableImage
        }
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1024,
            pixelsHigh: 1024,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw CustomAppIconError.renderingFailed
        }

        let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        let scale = min(
            canvas.width / image.size.width,
            canvas.height / image.size.height
        )
        let imageSize = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let destination = NSRect(
            x: (canvas.width - imageSize.width) / 2,
            y: (canvas.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(canvas)
        image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CustomAppIconError.renderingFailed
        }
        try png.write(to: container.customAppIconURL, options: .atomic)
        return container.customAppIconURL.lastPathComponent
    }

    func image(relativePath: String?) -> NSImage? {
        guard let relativePath,
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath else {
            return nil
        }
        return NSImage(
            contentsOf: container.rootURL.appendingPathComponent(relativePath)
        )
    }
}
