import Foundation

extension IrisProvider {

    /// An `IrisProvider` that calls a local Ollama server with a vision-capable model.
    ///
    /// Sends JPEG image data and a JSON Schema prompt to Ollama's chat API and returns
    /// the raw JSON string from the response message content.
    ///
    /// - Parameters:
    ///   - model: The Ollama model to use (e.g. `"llama3.2-vision"`, `"llava"`, `"bakllava"`).
    ///     The model must be pulled with `ollama pull <model>` before use.
    ///   - endpoint: The Ollama API endpoint. Defaults to `http://localhost:11434/api/chat`.
    /// - Returns: An `IrisProvider` configured to call the specified Ollama endpoint.
    /// - Throws: `IrisError.modelFailure` on HTTP 4xx/5xx responses;
    ///   `IrisError.networkError` on `URLError` — a `URLError.cannotConnectToHost` is
    ///   expected when Ollama is not running locally.
    ///
    /// - Note: No API key is required. All inference runs locally via Ollama.
    public static func ollama(
        model: String,
        endpoint: URL = URL(string: "http://localhost:11434/api/chat")!
    ) -> IrisProvider {
        ollama(model: model, endpoint: endpoint, session: .shared)
    }

    // Internal testable seam
    static func ollama(model: String, endpoint: URL, session: URLSession) -> IrisProvider {
        IrisProvider { imageData, prompt in
            let request = try OllamaRequest.build(imageData: imageData, prompt: prompt, model: model, endpoint: endpoint)
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError {
                throw IrisError.networkError(underlying: urlError)
            }
            guard let http = response as? HTTPURLResponse else {
                throw IrisError.modelFailure(message: "Unexpected non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw IrisError.modelFailure(message: body)
            }
            let decoded = try JSONDecoder.iris.decode(OllamaResponse.self, from: data)
            return decoded.message.content
        }
    }
}

// MARK: - Private Ollama API Types

private enum OllamaRequest {
    static func build(imageData: Data, prompt: String, model: String, endpoint: URL) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            stream: false,
            messages: [
                Message(
                    role: "user",
                    content: prompt,
                    images: [imageData.base64EncodedString()]
                )
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private struct RequestBody: Encodable {
        let model: String
        let stream: Bool
        let messages: [Message]
    }

    private struct Message: Encodable {
        let role: String
        let content: String
        let images: [String]
    }
}

private struct OllamaResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let content: String
    }
}
