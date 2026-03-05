import Foundation

enum ResponseDecoder {

    /// Decodes raw JSON string into the given `Decodable` type.
    /// On failure, wraps the original raw JSON in `IrisError.decodingFailed`.
    static func decode<T: Decodable>(_ type: T.Type, from rawJSON: String) throws -> T {
        guard let data = rawJSON.data(using: .utf8) else {
            throw IrisError.decodingFailed(raw: rawJSON)
        }
        do {
            return try JSONDecoder.iris.decode(type, from: data)
        } catch {
            throw IrisError.decodingFailed(raw: rawJSON)
        }
    }
}

// MARK: - Shared decoder — single configuration source for all JSON decoding in Iris

extension JSONDecoder {
    static let iris: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
