#if canImport(AppKit) && !canImport(UIKit)
import AppKit

extension ImagePipeline {
    static func normalize(nsImage: NSImage) throws -> Data {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw IrisError.imageUnreadable(reason: "NSImage could not be converted to CGImage")
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: Float(jpegQuality)]) else {
            throw IrisError.imageUnreadable(reason: "NSBitmapImageRep could not produce JPEG data")
        }
        return data
    }

    static func normalizeData(_ data: Data) throws -> Data {
        guard let image = NSImage(data: data) else {
            throw IrisError.imageUnreadable(reason: "Data could not be decoded as an NSImage")
        }
        return try normalize(nsImage: image)
    }
}
#endif
