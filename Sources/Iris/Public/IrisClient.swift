import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

public actor IrisClient {

    let model: IrisModel        // internal let: accessible via @testable import for tests
    let retryPolicy: RetryPolicy
    let debugMode: Bool
    public private(set) var lastDebugInfo: IrisDebugInfo?

    // MARK: - Public Initializers

    /// Creates a client with an explicit API key.
    public init(apiKey: String, retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        self.model = IrisModel.claude(apiKey: apiKey)
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    /// Creates a client with an explicit API key and custom model.
    /// The provided model overrides the default Claude model.
    public init(apiKey: String, model: IrisModel, debugMode: Bool = false) {
        self.model = model
        self.retryPolicy = .none
        self.debugMode = debugMode
    }

    /// Creates a client using the `ANTHROPIC_API_KEY` environment variable.
    /// If the key is absent or empty, each `parse` call throws `IrisError.invalidAPIKey`
    /// without making any network calls.
    public init(retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        self.init(environment: ProcessInfo.processInfo.environment, retryPolicy: retryPolicy, debugMode: debugMode)
    }

    // MARK: - Internal Initializers

    /// Injects a pre-built model directly.
    public init(model: IrisModel, retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        self.model = model
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    /// Reads `ANTHROPIC_API_KEY` from the given environment dictionary.
    /// Allows deterministic testing without mutating the process environment.
    init(environment: [String: String], retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        let envKey = environment["ANTHROPIC_API_KEY"] ?? ""
        if envKey.isEmpty {
            self.model = IrisModel { _, _ in throw IrisError.invalidAPIKey }
        } else {
            self.model = IrisModel.claude(apiKey: envKey)
        }
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    // MARK: - Parse Overloads

    /// Parses raw image data with an explicit MIME type into the target `Decodable` type.
    public func parse<T: Decodable>(data: Data, mimeType: String, as type: T.Type) async throws -> T {
        // Stage 1: Image normalization
        IrisLogger.image.debug("Normalizing image [\(mimeType, privacy: .public)]")
        let imageData: Data
        do {
            imageData = try ImagePipeline.normalize(data: data, mimeType: mimeType)
        } catch {
            IrisLogger.image.error("Image normalization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let prompt = PromptBuilder.build(for: type)

        // Stage 2: Model call
        IrisLogger.network.debug("Invoking model parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.model.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Model parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Model parse completed")

        if debugMode {
            lastDebugInfo = IrisDebugInfo(ocrText: rawJSON, rawJSON: rawJSON)
        }

        // Stage 3: Decoding
        IrisLogger.decode.debug("Decoding response into \(String(describing: type), privacy: .public)")
        do {
            let result = try ResponseDecoder.decode(type, from: rawJSON)
            IrisLogger.decode.debug("Decode succeeded")
            return result
        } catch {
            IrisLogger.decode.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Parses an image file at the given URL into the target `Decodable` type.
    public func parse<T: Decodable>(fileURL: URL, as type: T.Type) async throws -> T {
        // Stage 1: Image normalization
        IrisLogger.image.debug("Normalizing image from file: \(fileURL.lastPathComponent, privacy: .public)")
        let imageData: Data
        do {
            imageData = try ImagePipeline.normalize(url: fileURL)
        } catch {
            IrisLogger.image.error("Image normalization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let prompt = PromptBuilder.build(for: type)

        // Stage 2: Model call
        IrisLogger.network.debug("Invoking model parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.model.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Model parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Model parse completed")

        if debugMode {
            lastDebugInfo = IrisDebugInfo(ocrText: rawJSON, rawJSON: rawJSON)
        }

        // Stage 3: Decoding
        IrisLogger.decode.debug("Decoding response into \(String(describing: type), privacy: .public)")
        do {
            let result = try ResponseDecoder.decode(type, from: rawJSON)
            IrisLogger.decode.debug("Decode succeeded")
            return result
        } catch {
            IrisLogger.decode.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    #if canImport(UIKit)
    /// Parses a `UIImage` into the target `Decodable` type.
    public func parse<T: Decodable>(image: UIImage, as type: T.Type) async throws -> T {
        // Stage 1: Image normalization
        IrisLogger.image.debug("Normalizing UIImage")
        let imageData: Data
        do {
            imageData = try ImagePipeline.normalize(uiImage: image)
        } catch {
            IrisLogger.image.error("Image normalization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let prompt = PromptBuilder.build(for: type)

        // Stage 2: Model call
        IrisLogger.network.debug("Invoking model parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.model.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Model parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Model parse completed")

        if debugMode {
            lastDebugInfo = IrisDebugInfo(ocrText: rawJSON, rawJSON: rawJSON)
        }

        // Stage 3: Decoding
        IrisLogger.decode.debug("Decoding response into \(String(describing: type), privacy: .public)")
        do {
            let result = try ResponseDecoder.decode(type, from: rawJSON)
            IrisLogger.decode.debug("Decode succeeded")
            return result
        } catch {
            IrisLogger.decode.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    /// Parses an `NSImage` into the target `Decodable` type.
    public func parse<T: Decodable>(image: NSImage, as type: T.Type) async throws -> T {
        // Stage 1: Image normalization
        IrisLogger.image.debug("Normalizing NSImage")
        let imageData: Data
        do {
            imageData = try ImagePipeline.normalize(nsImage: image)
        } catch {
            IrisLogger.image.error("Image normalization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let prompt = PromptBuilder.build(for: type)

        // Stage 2: Model call
        IrisLogger.network.debug("Invoking model parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.model.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Model parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Model parse completed")

        if debugMode {
            lastDebugInfo = IrisDebugInfo(ocrText: rawJSON, rawJSON: rawJSON)
        }

        // Stage 3: Decoding
        IrisLogger.decode.debug("Decoding response into \(String(describing: type), privacy: .public)")
        do {
            let result = try ResponseDecoder.decode(type, from: rawJSON)
            IrisLogger.decode.debug("Decode succeeded")
            return result
        } catch {
            IrisLogger.decode.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    #endif
}
