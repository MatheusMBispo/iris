public struct IrisDebugInfo: Sendable {
    public let ocrText: String
    public let rawJSON: String

    public init(ocrText: String, rawJSON: String) {
        self.ocrText = ocrText
        self.rawJSON = rawJSON
    }
}
