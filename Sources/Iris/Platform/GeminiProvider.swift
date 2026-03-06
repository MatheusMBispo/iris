import Foundation

extension IrisProvider {

    /// An `IrisProvider` that calls the Google Gemini Vision API.
    ///
    /// Sends JPEG image data and a JSON Schema prompt to the Gemini API and returns
    /// the raw JSON string from the first candidate's content.
    ///
    /// - Parameters:
    ///   - apiKey: Your Google AI API key (`AIza...`).
    ///   - model: The model to use. Defaults to `"gemini-2.0-flash"` (fast, vision-capable, free tier available).
    /// - Returns: An `IrisProvider` configured to call the Gemini `generateContent` endpoint.
    /// - Throws: `IrisError.invalidAPIKey` on HTTP 400/403 with API key error; `IrisError.modelFailure`
    ///   on other HTTP errors or empty candidates; `IrisError.networkError` on `URLError`.
    ///
    /// - Note: The API key is passed as a URL query parameter (`?key=`), not in an `Authorization` header.
    ///   This is Google's API design for Gemini.
    public static func gemini(apiKey: String, model: String = "gemini-2.0-flash") -> IrisProvider {
        gemini(apiKey: apiKey, model: model, session: .shared)
    }

    // Internal testable seam
    static func gemini(apiKey: String, model: String, session: URLSession) -> IrisProvider {
        IrisProvider { imageData, prompt in
            let request = try GeminiRequest.build(imageData: imageData, prompt: prompt, apiKey: apiKey, model: model)
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError {
                throw IrisError.networkError(underlying: urlError)
            }
            guard let http = response as? HTTPURLResponse else {
                throw IrisError.modelFailure(message: "Unexpected non-HTTP response")
            }
            if http.statusCode == 400 || http.statusCode == 403 {
                let parsed = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)
                let status = parsed?.error?.status ?? ""
                let message = (parsed?.error?.message ?? "").lowercased()
                let isAPIKeyError =
                    status == "PERMISSION_DENIED" ||
                    status == "INVALID_ARGUMENT" ||
                    message.contains("api key") ||
                    message.contains("apikey")
                if http.statusCode == 403 || isAPIKeyError {
                    throw IrisError.invalidAPIKey
                }
                let body = String(data: data, encoding: .utf8) ?? "Unknown Gemini error"
                throw IrisError.modelFailure(message: body)
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw IrisError.modelFailure(message: body)
            }
            let decoded = try JSONDecoder.iris.decode(GeminiResponse.self, from: data)
            guard let text = decoded.candidates.first?.content.parts.first?.text else {
                throw IrisError.modelFailure(message: "No candidates in Gemini response")
            }
            return normalizeProviderJSONOutput(text, schemaPrompt: prompt)
        }
    }
}

// MARK: - Private Gemini API Types

private enum GeminiRequest {
    static func build(imageData: Data, prompt: String, apiKey: String, model: String) throws -> URLRequest {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let endpoint = components.url else {
            throw IrisError.modelFailure(message: "Invalid Gemini endpoint URL")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            contents: [
                Content(parts: [
                    Part.inlineData(InlineDataPart(
                        inlineData: InlineData(mimeType: "image/jpeg", data: imageData.base64EncodedString())
                    )),
                    Part.text(TextPart(text: prompt))
                ])
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private struct RequestBody: Encodable {
        let contents: [Content]
    }

    private struct Content: Encodable {
        let parts: [Part]
    }

    private enum Part: Encodable {
        case inlineData(InlineDataPart)
        case text(TextPart)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .inlineData(let p): try p.encode(to: encoder)
            case .text(let p): try p.encode(to: encoder)
            }
        }
    }

    private struct InlineDataPart: Encodable {
        let inlineData: InlineData
        enum CodingKeys: String, CodingKey {
            case inlineData = "inline_data"
        }
    }

    private struct InlineData: Encodable {
        let mimeType: String
        let data: String
        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    private struct TextPart: Encodable {
        let text: String
    }
}

private struct GeminiErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let code: Int
        let status: String
        let message: String?
    }
    let error: ErrorBody?
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}
