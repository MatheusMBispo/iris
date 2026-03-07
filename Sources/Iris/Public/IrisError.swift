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

    /// The AI provider returned an error response or refused to process the input.
    ///
    /// Thrown on HTTP error responses from the provider (excluding authentication errors),
    /// or when the model explicitly declines to answer.
    ///
    /// - Parameter message: The raw error body returned by the provider.
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
    /// Wraps the underlying transport error so callers can inspect connectivity details.
    /// The associated value is `any Error` rather than `URLError` because some providers
    /// may surface non-URL transport failures.
    ///
    /// - Parameter underlying: The original error thrown by the transport layer.
    case networkError(underlying: any Error)

    /// The provided API key was rejected or no API key was supplied.
    ///
    /// Thrown when the required API key is absent or empty, or when the provider
    /// rejects the key as invalid or unauthorized.
    case invalidAPIKey
}
