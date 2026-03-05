import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

public actor IrisClient {

    let model: IrisModel  // internal let: accessible via @testable import for tests

    // MARK: - Public Initializers

    /// Creates a client with an explicit API key.
    public init(apiKey: String) {
        self.model = IrisModel.claude(apiKey: apiKey)
    }

    /// Creates a client using the `ANTHROPIC_API_KEY` environment variable.
    /// If the key is absent or empty, each `parse` call throws `IrisError.invalidAPIKey`
    /// without making any network calls.
    public init() {
        self.init(environment: ProcessInfo.processInfo.environment)
    }

    // MARK: - Internal Initializers

    /// Injects a pre-built model directly. Used for testing.
    init(model: IrisModel) {
        self.model = model
    }

    /// Reads `ANTHROPIC_API_KEY` from the given environment dictionary.
    /// Allows deterministic testing without mutating the process environment.
    init(environment: [String: String]) {
        let envKey = environment["ANTHROPIC_API_KEY"] ?? ""
        if envKey.isEmpty {
            self.model = IrisModel { _, _ in throw IrisError.invalidAPIKey }
        } else {
            self.model = IrisModel.claude(apiKey: envKey)
        }
    }

    // MARK: - Parse Overloads

    /// Parses raw image data with an explicit MIME type into the target `Decodable` type.
    public func parse<T: Decodable>(data: Data, mimeType: String, as type: T.Type) async throws -> T {
        let imageData = try ImagePipeline.normalize(data: data, mimeType: mimeType)
        let prompt = PromptBuilder.build(for: type)
        let rawJSON = try await model.parse(imageData, prompt)
        return try ResponseDecoder.decode(type, from: rawJSON)
    }

    /// Parses an image file at the given URL into the target `Decodable` type.
    public func parse<T: Decodable>(fileURL: URL, as type: T.Type) async throws -> T {
        let imageData = try ImagePipeline.normalize(url: fileURL)
        let prompt = PromptBuilder.build(for: type)
        let rawJSON = try await model.parse(imageData, prompt)
        return try ResponseDecoder.decode(type, from: rawJSON)
    }

    #if canImport(UIKit)
    /// Parses a `UIImage` into the target `Decodable` type.
    public func parse<T: Decodable>(image: UIImage, as type: T.Type) async throws -> T {
        let imageData = try ImagePipeline.normalize(uiImage: image)
        let prompt = PromptBuilder.build(for: type)
        let rawJSON = try await model.parse(imageData, prompt)
        return try ResponseDecoder.decode(type, from: rawJSON)
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    /// Parses an `NSImage` into the target `Decodable` type.
    public func parse<T: Decodable>(image: NSImage, as type: T.Type) async throws -> T {
        let imageData = try ImagePipeline.normalize(nsImage: image)
        let prompt = PromptBuilder.build(for: type)
        let rawJSON = try await model.parse(imageData, prompt)
        return try ResponseDecoder.decode(type, from: rawJSON)
    }
    #endif
}
