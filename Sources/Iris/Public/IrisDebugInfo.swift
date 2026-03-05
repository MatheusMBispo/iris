/// Raw diagnostic data captured during a parse operation when debug mode is enabled.
///
/// Access via `await irisClient.lastDebugInfo` after a `parse` call completes.
/// This property is `nil` when `IrisClient` was initialized with `debugMode: false` (the default).
///
/// ```swift
/// let iris = IrisClient(apiKey: key, debugMode: true)
/// let result = try await iris.parse(data: data, mimeType: "image/jpeg", as: MyStruct.self)
/// if let debug = await iris.lastDebugInfo {
///     print(debug.ocrText)
///     print(debug.rawJSON)
/// }
/// ```
public struct IrisDebugInfo: Sendable {

    /// The raw text extracted from the image before it was sent to the model.
    ///
    /// This is the OCR-equivalent output — the textual representation the model
    /// derived from the image. Useful for diagnosing why a field was `nil` due to
    /// unreadable text vs. a missing schema field.
    public let ocrText: String

    /// The raw JSON string returned by the model before it was decoded into the target type.
    ///
    /// Inspect this to diagnose `IrisError.decodingFailed` — the JSON here is exactly
    /// what the model produced, before any `JSONDecoder` processing.
    public let rawJSON: String

    /// Creates a debug info snapshot. Called internally by `IrisClient` — not intended for external use.
    public init(ocrText: String, rawJSON: String) {
        self.ocrText = ocrText
        self.rawJSON = rawJSON
    }
}
