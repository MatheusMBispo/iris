import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// The main entry point for all Iris document parsing operations.
///
/// `IrisClient` is an `actor` — all `parse` calls execute off the main actor,
/// guaranteeing zero UI blocking.
///
/// **Quick start:**
/// ```swift
/// let iris = IrisClient(apiKey: "sk-ant-...")
/// let receipt = try await iris.parse(data: jpegData, mimeType: "image/jpeg", as: Receipt.self)
/// ```
///
/// Use `IrisProvider.mock` in tests to avoid real API calls:
/// ```swift
/// let iris = IrisClient(provider: .mock)
/// ```
public actor IrisClient {

    let provider: IrisProvider        // internal let: accessible via @testable import for tests
    let retryPolicy: RetryPolicy
    let debugMode: Bool

    /// The raw diagnostic data from the most recent `parse` call, or `nil` if debug mode is disabled.
    ///
    /// Always `nil` when `IrisClient` was initialized with `debugMode: false` (the default).
    /// Updated after each `parse` call — whether it succeeds or throws.
    ///
    /// Access requires `await` because `IrisClient` is an actor:
    /// ```swift
    /// if let info = await iris.lastDebugInfo {
    ///     print(info.rawJSON)
    /// }
    /// ```
    public private(set) var lastDebugInfo: IrisDebugInfo?

    // MARK: - Public Initializers

    /// Creates a client with an explicit API key.
    public init(apiKey: String, retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        self.provider = IrisProvider.claude(apiKey: apiKey)
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    /// Creates a client with an explicit API key and custom provider.
    /// The provided provider overrides the default Claude provider.
    public init(apiKey: String, provider: IrisProvider, debugMode: Bool = false) {
        self.provider = provider
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

    /// Injects a pre-built provider directly.
    public init(provider: IrisProvider, retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        self.provider = provider
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    /// Reads `ANTHROPIC_API_KEY` from the given environment dictionary.
    /// Allows deterministic testing without mutating the process environment.
    init(environment: [String: String], retryPolicy: RetryPolicy = .none, debugMode: Bool = false) {
        let envKey = environment["ANTHROPIC_API_KEY"] ?? ""
        if envKey.isEmpty {
            self.provider = IrisProvider { _, _ in throw IrisError.invalidAPIKey }
        } else {
            self.provider = IrisProvider.claude(apiKey: envKey)
        }
        self.retryPolicy = retryPolicy
        self.debugMode = debugMode
    }

    // MARK: - Parse Overloads

    /// Parses raw image data with an explicit MIME type into the target `Decodable` type.
    ///
    /// - Parameters:
    ///   - data: Raw image bytes. Supported MIME types: `"image/jpeg"`, `"image/png"`, `"image/webp"`, `"image/gif"`.
    ///   - mimeType: The MIME type string describing the `data` format.
    ///   - type: The `Decodable` type to decode the provider response into.
    /// - Returns: A fully populated instance of `T`.
    /// - Throws: `IrisError.imageUnreadable` if the data cannot be normalized to JPEG.
    ///           `IrisError.networkError` if a connectivity failure occurs.
    ///           `IrisError.invalidAPIKey` if the API key is missing or rejected.
    ///           `IrisError.modelFailure` if the provider returns an error response.
    ///           `IrisError.decodingFailed` if the provider output cannot be decoded into `T`.
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

        // Stage 2: Provider call
        IrisLogger.network.debug("Invoking provider parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.provider.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Provider parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Provider parse completed")

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
    ///
    /// - Parameters:
    ///   - fileURL: A file URL pointing to the image to parse.
    ///   - type: The `Decodable` type to decode the provider response into.
    /// - Returns: A fully populated instance of `T`.
    /// - Throws: `IrisError.imageUnreadable` if the file cannot be read or normalized to JPEG.
    ///           `IrisError.networkError` if a connectivity failure occurs.
    ///           `IrisError.invalidAPIKey` if the API key is missing or rejected.
    ///           `IrisError.modelFailure` if the provider returns an error response.
    ///           `IrisError.decodingFailed` if the provider output cannot be decoded into `T`.
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

        // Stage 2: Provider call
        IrisLogger.network.debug("Invoking provider parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.provider.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Provider parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Provider parse completed")

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
    ///
    /// - Parameters:
    ///   - image: The `UIImage` to parse.
    ///   - type: The `Decodable` type to decode the provider response into.
    /// - Returns: A fully populated instance of `T`.
    /// - Throws: `IrisError.imageUnreadable` if the image cannot be normalized to JPEG.
    ///           `IrisError.networkError` if a connectivity failure occurs.
    ///           `IrisError.invalidAPIKey` if the API key is missing or rejected.
    ///           `IrisError.modelFailure` if the provider returns an error response.
    ///           `IrisError.decodingFailed` if the provider output cannot be decoded into `T`.
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

        // Stage 2: Provider call
        IrisLogger.network.debug("Invoking provider parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.provider.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Provider parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Provider parse completed")

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
    ///
    /// - Parameters:
    ///   - image: The `NSImage` to parse.
    ///   - type: The `Decodable` type to decode the provider response into.
    /// - Returns: A fully populated instance of `T`.
    /// - Throws: `IrisError.imageUnreadable` if the image cannot be normalized to JPEG.
    ///           `IrisError.networkError` if a connectivity failure occurs.
    ///           `IrisError.invalidAPIKey` if the API key is missing or rejected.
    ///           `IrisError.modelFailure` if the provider returns an error response.
    ///           `IrisError.decodingFailed` if the provider output cannot be decoded into `T`.
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

        // Stage 2: Provider call
        IrisLogger.network.debug("Invoking provider parse")
        let rawJSON: String
        do {
            rawJSON = try await RetryEngine.execute(policy: retryPolicy) { try await self.provider.parse(imageData, prompt) }
        } catch {
            IrisLogger.network.error("Provider parse failed: \(error.localizedDescription, privacy: .public)")
            if debugMode {
                let captured = String(describing: error)
                lastDebugInfo = IrisDebugInfo(ocrText: captured, rawJSON: captured)
            }
            throw error
        }
        IrisLogger.network.debug("Provider parse completed")

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
