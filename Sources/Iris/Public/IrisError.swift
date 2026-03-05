/// The error taxonomy for all failures that can occur during an Iris parse operation.
///
/// Every `IrisClient.parse` call maps underlying system and API errors to one of these
/// cases, so callers only need to handle typed Iris-specific failures.
public enum IrisError: Error, Sendable {

    /// The input image could not be read or converted to a format the model can process.
    ///
    /// Common causes: corrupted image data, unsupported MIME type, zero-byte input.
    ///
    /// - Parameter reason: A human-readable description of why the image was unreadable.
    case imageUnreadable(reason: String)

    /// The AI model returned an error response or refused to process the input.
    ///
    /// Thrown on HTTP 4xx/5xx responses from the Anthropic API (excluding 401),
    /// or when the model explicitly declines to answer.
    ///
    /// - Parameter message: The raw error body returned by the model or API.
    case modelFailure(message: String)

    /// The model's response could not be decoded into the requested `Decodable` type.
    ///
    /// Thrown when the raw JSON returned by the model does not match the expected schema.
    /// Inspect `raw` to diagnose schema mismatches.
    ///
    /// - Parameter raw: The raw JSON string that failed to decode.
    case decodingFailed(raw: String)

    /// A network-level failure occurred while communicating with the AI provider.
    ///
    /// Wraps the underlying `URLError` so callers can inspect connectivity details
    /// without depending on `Foundation` error types directly.
    ///
    /// - Parameter underlying: The original `URLError` thrown by `URLSession`.
    case networkError(underlying: any Error)

    /// The provided API key was rejected (HTTP 401) or no API key was supplied.
    ///
    /// Thrown when the `ANTHROPIC_API_KEY` environment variable is absent or empty,
    /// or when the Anthropic API returns an HTTP 401 Unauthorized response.
    case invalidAPIKey
}
