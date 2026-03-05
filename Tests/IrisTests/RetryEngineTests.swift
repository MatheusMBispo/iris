import Foundation
import Testing
@testable import Iris

// MARK: - Helpers

private final class CaptureBox<T>: @unchecked Sendable {
    var value: T
    init(_ initial: T) { value = initial }
}

// MARK: - RetryEngineTests

@Suite("RetryEngine")
struct RetryEngineTests {

    // MARK: - RetryPolicy.none

    @Test("none — operation called once, error propagates immediately")
    func nonePolicy() async throws {
        let callCount = CaptureBox(0)
        let result = try? await RetryEngine.execute(policy: .none) {
            callCount.value += 1
            throw IrisError.networkError(underlying: URLError(.timedOut))
            return ""
        }
        #expect(result == nil)
        #expect(callCount.value == 1)
    }

    // MARK: - Retry behavior

    @Test("custom policy — retries networkError, stops at maxAttempts")
    func retriesNetworkError() async throws {
        let callCount = CaptureBox(0)
        let fastPolicy = RetryPolicy { error, attempt in
            guard case .networkError = error else { return false }
            return attempt < 3  // total 3 attempts
        }
        do {
            _ = try await RetryEngine.execute(policy: fastPolicy) {
                callCount.value += 1
                throw IrisError.networkError(underlying: URLError(.timedOut))
                return ""
            }
        } catch {}
        #expect(callCount.value == 3)
    }

    @Test("custom policy — does NOT retry decodingFailed")
    func doesNotRetryDecodingFailed() async throws {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy { error, attempt in
            guard case .networkError = error else { return false }
            return attempt < 3
        }
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                callCount.value += 1
                throw IrisError.decodingFailed(raw: "{}")
                return ""
            }
        } catch {}
        #expect(callCount.value == 1)
    }

    @Test("custom policy — does NOT retry imageUnreadable")
    func doesNotRetryImageUnreadable() async throws {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy { error, attempt in
            guard case .networkError = error else { return false }
            return attempt < 3
        }
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                callCount.value += 1
                throw IrisError.imageUnreadable(reason: "bad data")
                return ""
            }
        } catch {}
        #expect(callCount.value == 1)
    }

    @Test("custom policy — does NOT retry invalidAPIKey")
    func doesNotRetryInvalidAPIKey() async throws {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy { error, attempt in
            guard case .networkError = error else { return false }
            return attempt < 3
        }
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                callCount.value += 1
                throw IrisError.invalidAPIKey
                return ""
            }
        } catch {}
        #expect(callCount.value == 1)
    }

    @Test("last error from final attempt propagates to caller")
    func lastErrorPropagates() async throws {
        let policy = RetryPolicy { _, attempt in attempt < 2 }
        var thrownError: IrisError?
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                throw IrisError.networkError(underlying: URLError(.timedOut))
                return ""
            }
        } catch let e as IrisError {
            thrownError = e
        }
        if case .networkError = thrownError { } else {
            Issue.record("Expected networkError, got \(String(describing: thrownError))")
        }
    }

    @Test("attempt number is 1-based and increments per retry")
    func attemptNumbering() async throws {
        let receivedAttempts = CaptureBox([Int]())
        let policy = RetryPolicy { error, attempt in
            receivedAttempts.value.append(attempt)
            return attempt < 3
        }
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                throw IrisError.networkError(underlying: URLError(.timedOut))
                return ""
            }
        } catch {}
        #expect(receivedAttempts.value == [1, 2, 3])
    }
}
