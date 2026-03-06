import Foundation

extension IrisProvider {

    /// An `IrisProvider` that calls the OpenAI Chat Completions API (GPT-4o Vision).
    ///
    /// Sends JPEG image data and a JSON Schema prompt to the OpenAI API and returns
    /// the raw JSON string from the first choice's message content.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenAI API key (`sk-...`).
    ///   - model: The model to use. Defaults to `"gpt-4o"` (vision-capable).
    /// - Returns: An `IrisProvider` configured to call `https://api.openai.com/v1/chat/completions`.
    /// - Throws: `IrisError.invalidAPIKey` on HTTP 401; `IrisError.modelFailure` on other HTTP errors
    ///   or empty choices; `IrisError.networkError` on `URLError`.
    public static func openAI(apiKey: String, model: String = "gpt-4o") -> IrisProvider {
        openAI(apiKey: apiKey, model: model, session: .shared)
    }

    // Internal testable seam
    static func openAI(apiKey: String, model: String, session: URLSession) -> IrisProvider {
        IrisProvider { imageData, prompt in
            let request = try OpenAIRequest.build(imageData: imageData, prompt: prompt, apiKey: apiKey, model: model)
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
            let decoded = try JSONDecoder.iris.decode(OpenAIResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw IrisError.modelFailure(message: "No choices in OpenAI response")
            }
            return content
        }
    }
}

// MARK: - Private OpenAI API Types

private enum OpenAIRequest {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let maxTokens = 4096

    static func build(imageData: Data, prompt: String, apiKey: String, model: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            messages: [
                Message(role: "user", content: [
                    ContentBlock.imageURL(ImageURLBlock(
                        imageUrl: ImageURL(url: "data:image/jpeg;base64,\(imageData.base64EncodedString())")
                    )),
                    ContentBlock.text(TextBlock(text: prompt))
                ])
            ]
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

    private enum ContentBlock: Encodable {
        case imageURL(ImageURLBlock)
        case text(TextBlock)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .imageURL(let block): try block.encode(to: encoder)
            case .text(let block): try block.encode(to: encoder)
            }
        }
    }

    private struct ImageURLBlock: Encodable {
        let type = "image_url"
        let imageUrl: ImageURL
        enum CodingKeys: String, CodingKey {
            case type
            case imageUrl = "image_url"
        }
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    private struct TextBlock: Encodable {
        let type = "text"
        let text: String
    }
}

private struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}
