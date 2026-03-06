import Foundation

/// A Protocol Witnesses struct that encapsulates an AI provider's parsing behavior.
///
/// `IrisProvider` provides the boundary between `IrisClient` and any AI provider.
/// The default implementation is `IrisProvider.claude`, which calls the Anthropic Messages API.
/// Use `IrisProvider.mock` in tests and SwiftUI Previews to avoid real network calls.
///
/// Custom providers can be injected without changing any call-site syntax:
/// ```swift
/// let custom = IrisProvider { imageData, prompt in
///     return #"{"storeName": "Iris Store", "total": 42.0}"#
/// }
/// let iris = IrisClient(apiKey: key, provider: custom)
/// ```
public struct IrisProvider: Sendable {

    /// The underlying parsing closure that receives image data and a prompt, returning raw JSON.
    ///
    /// - Parameters:
    ///   - imageData: JPEG-encoded image data to analyze.
    ///   - prompt: A JSON Schema prompt describing the fields to extract.
    /// - Returns: A raw JSON string matching the requested schema.
    /// - Throws: Any `IrisError` variant appropriate to the failure.
    public var parse: @Sendable (_ imageData: Data, _ prompt: String) async throws -> String

    /// Creates a custom `IrisProvider` from a parsing closure.
    ///
    /// - Parameter parse: The async throwing closure that implements provider parsing.
    public init(parse: @escaping @Sendable (_ imageData: Data, _ prompt: String) async throws -> String) {
        self.parse = parse
    }

    // MARK: - Public Factory

    /// The default Claude provider implementation using the Anthropic Messages API via URLSession.
    ///
    /// Sends JPEG image data and a JSON Schema prompt to the Anthropic API and returns
    /// the raw JSON string from the provider's first text content block.
    ///
    /// - Parameter apiKey: Your Anthropic API key.
    /// - Returns: An `IrisProvider` configured to call `https://api.anthropic.com/v1/messages`.
    public static func claude(apiKey: String) -> IrisProvider {
        claude(apiKey: apiKey, session: .shared)
    }

    // MARK: - Mock Factory

    /// A mock provider that returns a hardcoded empty JSON object without making any network calls.
    ///
    /// Use `IrisProvider.mock` in unit tests and SwiftUI Previews to avoid real API calls.
    /// The mock returns `"{}"`, which decodes to a struct where all `Optional` fields are `nil`.
    ///
    /// ```swift
    /// let iris = IrisClient(provider: .mock)
    /// let result = try await iris.parse(data: data, mimeType: "image/jpeg", as: MyStruct.self)
    /// // result.anyOptionalField == nil
    /// ```
    public static let mock = IrisProvider { _, _ in "{}" }

    // MARK: - Internal Factory (testable via injected session)

    static func claude(apiKey: String, session: URLSession) -> IrisProvider {
        IrisProvider { imageData, prompt in
            let request = try AnthropicRequest.build(imageData: imageData, prompt: prompt, apiKey: apiKey)
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError {
                throw IrisError.networkError(underlying: urlError)
            }
            guard let http = response as? HTTPURLResponse else {
                throw IrisError.modelFailure(message: "Unexpected non-HTTP response")
            }
            if http.statusCode == 401 {
                throw IrisError.invalidAPIKey
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw IrisError.modelFailure(message: body)
            }
            let decoded = try JSONDecoder.iris.decode(AnthropicResponse.self, from: data)
            guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
                throw IrisError.modelFailure(message: "No text content in Anthropic response")
            }
            return text
        }
    }
}

// MARK: - Private Anthropic API Types

private enum AnthropicRequest {
    static let endpointString = "https://api.anthropic.com/v1/messages"
    static let model = "claude-opus-4-5"
    static let maxTokens = 4096
    static let anthropicVersion = "2023-06-01"

    static func build(imageData: Data, prompt: String, apiKey: String) throws -> URLRequest {
        guard let endpoint = URL(string: endpointString) else {
            throw IrisError.modelFailure(message: "Invalid Anthropic endpoint URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            messages: [Message(role: "user", content: [
                ContentBlock(type: "image", source: ImageSource(
                    type: "base64",
                    mediaType: "image/jpeg",
                    data: imageData.base64EncodedString()
                ), text: nil),
                ContentBlock(type: "text", source: nil, text: prompt)
            ])]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let messages: [Message]
        enum CodingKeys: String, CodingKey {
            case model, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    private struct ContentBlock: Encodable {
        let type: String
        let source: ImageSource?
        let text: String?
    }

    private struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String
        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }
}

private struct AnthropicResponse: Decodable {
    let content: [ContentItem]

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }
}
