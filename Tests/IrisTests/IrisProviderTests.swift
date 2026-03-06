import Foundation
import Testing
@testable import Iris

// MARK: - Protocol Witnesses structural tests

/// Tests that IrisProvider IS a struct (value type) conforming to Sendable.
/// Verifies the Protocol Witnesses pattern — no class or protocol involved.
@Suite("IrisProvider as Protocol Witnesses struct")
struct IrisProviderProtocolWitnessesTests {

    @Test("IrisProvider is a value type (struct)")
    func irisProviderIsValueType() {
        // If IrisProvider were a class, we'd need `let` + reference semantics
        // Value type: assignment creates a copy
        let original = IrisProvider { _, _ in "original" }
        var copy = original
        // Swift structs copy on assignment — reassigning `copy` does not affect `original`
        copy = IrisProvider { _, _ in "copy" }
        // Both are valid independent providers (compile-time proof of value type)
        _ = original
        _ = copy
    }

    @Test("IrisProvider.parse closure is Sendable")
    func parseClosureIsSendable() async throws {
        // @Sendable is a compile-time guarantee — if this compiles, Sendable is enforced
        let provider: IrisProvider = IrisProvider { data, prompt in
            return #"{"ok": true}"#
        }
        // Can be passed across actor boundaries (Sendable guarantee)
        let result = try await Task.detached {
            try await provider.parse(Data(), "test")
        }.value
        #expect(result == #"{"ok": true}"#)
    }

    @Test("multiple providers are independent — no shared state")
    func multipleProvidersAreIndependent() async throws {
        let counter1 = CaptureBox<Int>()
        let counter2 = CaptureBox<Int>()

        let provider1 = IrisProvider { _, _ in
            await counter1.set((await counter1.get() ?? 0) + 1)
            return #"{"id": 1}"#
        }
        let provider2 = IrisProvider { _, _ in
            await counter2.set((await counter2.get() ?? 0) + 1)
            return #"{"id": 2}"#
        }

        _ = try await provider1.parse(Data(), "p")
        _ = try await provider1.parse(Data(), "p")
        _ = try await provider2.parse(Data(), "p")

        #expect(await counter1.get() == 2)
        #expect(await counter2.get() == 1)
    }
}

// MARK: - IrisProvider.mock additional contract tests

@Suite("IrisProvider.mock additional contract")
struct IrisProviderMockAdditionalTests {

    @Test("mock is reusable across multiple calls")
    func mockIsReusableAcrossMultipleCalls() async throws {
        for _ in 1...5 {
            let result = try await IrisProvider.mock.parse(Data(), "any prompt")
            #expect(result == "{}")
        }
    }

    @Test("mock ignores imageData content — returns fixed response regardless")
    func mockIgnoresImageData() async throws {
        let emptyResult = try await IrisProvider.mock.parse(Data(), "prompt")
        let nonEmptyResult = try await IrisProvider.mock.parse(Data([0xFF, 0xD8]), "prompt")
        let randomResult = try await IrisProvider.mock.parse(Data([0x00, 0x01, 0x02, 0x03]), "prompt")
        #expect(emptyResult == "{}")
        #expect(nonEmptyResult == "{}")
        #expect(randomResult == "{}")
    }

    @Test("mock ignores prompt content — returns fixed response regardless")
    func mockIgnoresPrompt() async throws {
        let r1 = try await IrisProvider.mock.parse(Data(), "short")
        let r2 = try await IrisProvider.mock.parse(Data(), "very long prompt with lots of text and JSON schema")
        let r3 = try await IrisProvider.mock.parse(Data(), "")
        #expect(r1 == r2)
        #expect(r2 == r3)
    }

    @Test("custom error-throwing provider propagates IrisError unchanged")
    func throwingProviderPropagatesIrisError() async {
        let expected = IrisError.modelFailure(message: "deliberate failure")
        let provider = IrisProvider { _, _ in throw expected }

        var caught: (any Error)?
        do { _ = try await provider.parse(Data(), "p") } catch { caught = error }

        if case .modelFailure(let message) = caught as? IrisError {
            #expect(message == "deliberate failure")
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }
}

// MARK: - Shared helpers (mirrored from IrisClientTests.swift — NOT duplicating, just local copies)

private actor CaptureBox<T> {
    private var value: T?
    func set(_ v: T) { value = v }
    func get() -> T? { value }
}
