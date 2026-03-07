import Foundation

/// Determines whether a failed `IrisProvider.parse` call should be retried.
///
/// Use the built-in factories for common strategies or provide a custom closure:
/// ```swift
/// let client = IrisClient(apiKey: key, retryPolicy: .exponential(maxAttempts: 3))
/// ```
public struct RetryPolicy: Sendable {

    /// Returns `true` if the operation should be retried after the given error on the given attempt number.
    ///
    /// - Parameters:
    ///   - error: The `IrisError` thrown by the last attempt.
    ///   - attempt: 1-based attempt index of the attempt that just failed.
    public var shouldRetry: @Sendable (IrisError, _ attempt: Int) async -> Bool

    /// Creates a `RetryPolicy` with a custom retry closure.
    public init(shouldRetry: @escaping @Sendable (IrisError, _ attempt: Int) async -> Bool) {
        self.shouldRetry = shouldRetry
    }
}

extension RetryPolicy {

    /// No retries — every error is propagated immediately.
    public static let none = RetryPolicy { _, _ in false }

    /// Exponential backoff retrying only `IrisError.networkError`.
    ///
    /// - Parameter maxAttempts: Total number of attempts (including the first). Defaults to `3`.
    /// - Returns: A policy that retries up to `maxAttempts` times with `2^(attempt-1)` second delays.
    public static func exponential(maxAttempts: Int = 3) -> RetryPolicy {
        RetryPolicy { error, attempt in
            guard case .networkError = error else { return false }
            guard attempt < maxAttempts else { return false }
            let delay = pow(2.0, Double(attempt - 1))
            try? await Task.sleep(for: .seconds(delay))
            return true
        }
    }
}
