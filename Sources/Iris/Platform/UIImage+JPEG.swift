#if canImport(UIKit)
import UIKit

extension ImagePipeline {
    static func normalize(uiImage: UIImage) throws -> Data {
        guard let data = uiImage.jpegData(compressionQuality: jpegQuality) else {
            throw IrisError.imageUnreadable(reason: "UIImage could not be encoded as JPEG")
        }
        return data
    }

    static func normalizeData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw IrisError.imageUnreadable(reason: "Data could not be decoded as a UIImage")
        }
        return try normalize(uiImage: image)
    }
}
#endif
