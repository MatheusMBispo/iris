public enum IrisError: Error, Sendable {
    case imageUnreadable(reason: String)
    case modelFailure(message: String)
    case decodingFailed(raw: String)
    case networkError(underlying: any Error)
    case invalidAPIKey
}
