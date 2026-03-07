import Foundation
import Testing
@testable import Iris

// MARK: - Helpers

private actor CaptureBox<T> {
    private var value: T

    init(_ initial: T) { value = initial }

    func get() -> T { value }

    func set(_ newValue: T) { value = newValue }
}

// MARK: - RetryEngineTests

@Suite("RetryEngine")
struct RetryEngineTests {

    // MARK: - RetryPolicy.none

    @Test("none — operation called once, error propagates immediately")
    func nonePolicy() async throws {
        let callCount = CaptureBox(0)
        let result = try? await RetryEngine.execute(policy: .none) {
            let current = await callCount.get()
            await callCount.set(current + 1)
            throw IrisError.networkError(underlying: URLError(.timedOut))
        }
        #expect(result == nil)
        #expect(await callCount.get() == 1)
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
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.networkError(underlying: URLError(.timedOut))
            }
        } catch {}
        #expect(await callCount.get() == 3)
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
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.decodingFailed(raw: "{}")
            }
        } catch {}
        #expect(await callCount.get() == 1)
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
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.imageUnreadable(reason: "bad data")
            }
        } catch {}
        #expect(await callCount.get() == 1)
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
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.invalidAPIKey
            }
        } catch {}
        #expect(await callCount.get() == 1)
    }

    @Test("last error from final attempt propagates to caller")
    func lastErrorPropagates() async throws {
        let policy = RetryPolicy { _, attempt in attempt < 2 }
        var thrownError: IrisError?
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                throw IrisError.networkError(underlying: URLError(.timedOut))
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
            let current = await receivedAttempts.get()
            await receivedAttempts.set(current + [attempt])
            return attempt < 3
        }
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                throw IrisError.networkError(underlying: URLError(.timedOut))
            }
        } catch {}
        #expect(await receivedAttempts.get() == [1, 2, 3])
    }

    // MARK: - RetryPolicy.exponential factory tests

    @Test("exponential — does NOT retry decodingFailed (exits guard before sleep)")
    func exponential_doesNotRetryDecodingFailed() async {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy.exponential(maxAttempts: 3)
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.decodingFailed(raw: "{}")
            }
        } catch {}
        #expect(await callCount.get() == 1)  // not retried — decodingFailed returns false immediately
    }

    @Test("exponential — does NOT retry imageUnreadable (exits guard before sleep)")
    func exponential_doesNotRetryImageUnreadable() async {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy.exponential(maxAttempts: 3)
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.imageUnreadable(reason: "corrupt")
            }
        } catch {}
        #expect(await callCount.get() == 1)
    }

    @Test("exponential — does NOT retry invalidAPIKey (exits guard before sleep)")
    func exponential_doesNotRetryInvalidAPIKey() async {
        let callCount = CaptureBox(0)
        let policy = RetryPolicy.exponential(maxAttempts: 3)
        do {
            _ = try await RetryEngine.execute(policy: policy) {
                let current = await callCount.get()
                await callCount.set(current + 1)
                throw IrisError.invalidAPIKey
            }
        } catch {}
        #expect(await callCount.get() == 1)
    }
}
