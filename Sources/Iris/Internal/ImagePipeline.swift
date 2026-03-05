import Foundation

enum ImagePipeline {
    static let jpegQuality: CGFloat = 0.8

    private static let supportedMIMETypes: Set<String> = [
        "image/jpeg", "image/jpg", "image/png",
        "image/gif", "image/webp", "image/heic", "image/heif"
    ]

    static func normalize(url: URL) throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IrisError.imageUnreadable(
                reason: "Cannot read file at '\(url.lastPathComponent)': \(error.localizedDescription)"
            )
        }
        return try normalizeData(data)
    }

    static func normalize(data: Data, mimeType: String) throws -> Data {
        guard supportedMIMETypes.contains(mimeType.lowercased()) else {
            throw IrisError.imageUnreadable(
                reason: "Unsupported MIME type '\(mimeType)'. Supported types: image/jpeg, image/jpg, image/png, image/gif, image/webp, image/heic, image/heif"
            )
        }
        return try normalizeData(data)
    }
}
