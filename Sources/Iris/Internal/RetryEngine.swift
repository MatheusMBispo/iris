/// Executes an async operation with a caller-supplied retry policy.
///
/// Only `IrisError` throws are eligible for retry; any other error (e.g. `CancellationError`)
/// propagates immediately without consulting the policy.
enum RetryEngine {

    /// Runs `operation()` in a loop, consulting `policy.shouldRetry` after each `IrisError` failure.
    ///
    /// - Parameters:
    ///   - policy: Controls whether and how long to wait between attempts.
    ///   - operation: The work to execute. Must be `@Sendable` for Swift 6 concurrency safety.
    /// - Returns: The `String` returned by the first successful invocation.
    /// - Throws: The `IrisError` from the final failing attempt, or any non-`IrisError` error immediately.
    static func execute(
        policy: RetryPolicy,
        operation: @Sendable () async throws -> String
    ) async throws -> String {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as IrisError {
                guard await policy.shouldRetry(error, attempt) else { throw error }
                attempt += 1
            } catch {
                throw error  // CancellationError, etc. — no retry
            }
        }
    }
}
