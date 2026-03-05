import Foundation

public struct IrisModel: Sendable {
    public var parse: @Sendable (_ imageData: Data, _ prompt: String) async throws -> String

    public init(parse: @escaping @Sendable (_ imageData: Data, _ prompt: String) async throws -> String) {
        self.parse = parse
    }

    // MARK: - Public Factory

    public static func claude(apiKey: String) -> IrisModel {
        claude(apiKey: apiKey, session: .shared)
    }

    // MARK: - Mock Factory

    public static let mock = IrisModel { _, _ in "{}" }

    // MARK: - Internal Factory (testable via injected session)

    static func claude(apiKey: String, session: URLSession) -> IrisModel {
        IrisModel { imageData, prompt in
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
    // Known-good hard-coded URL — cannot be nil
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-4-5"
    static let maxTokens = 4096
    static let anthropicVersion = "2023-06-01"

    static func build(imageData: Data, prompt: String, apiKey: String) throws -> URLRequest {
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
