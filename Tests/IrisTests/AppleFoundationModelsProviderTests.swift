import Foundation
import Testing
@testable import Iris

// MARK: - extractJSON helper tests (no @available needed — pure String helper)

#if canImport(FoundationModels)

@Suite("extractJSON helper")
struct ExtractJSONHelperTests {

    @Test("plain JSON passes through unchanged (whitespace trimmed)")
    func plainJSON_passesThroughTrimmed() {
        let input = "  {\"key\": \"value\"}  "
        let result = extractJSON(from: input)
        #expect(result == "{\"key\": \"value\"}")
    }

    @Test("strips ```json code fence")
    func stripsJSONCodeFence() {
        let input = """
        ```json
        {"key": "value"}
        ```
        """
        let result = extractJSON(from: input)
        #expect(result == "{\"key\": \"value\"}")
    }

    @Test("strips plain ``` code fence")
    func stripsPlainCodeFence() {
        let input = """
        ```
        {"key": "value"}
        ```
        """
        let result = extractJSON(from: input)
        #expect(result == "{\"key\": \"value\"}")
    }

    @Test("empty string returns empty string")
    func emptyStringReturnsEmpty() {
        let result = extractJSON(from: "")
        #expect(result == "")
    }

    @Test("multi-line JSON inside code fence preserves structure")
    func multilineJSONInsideCodeFence() {
        let input = """
        ```json
        {
          "store": "Whole Foods Market",
          "total": 42.0
        }
        ```
        """
        let result = extractJSON(from: input)
        // Content between fences should be preserved (inner lines)
        #expect(result.contains("Whole Foods Market"))
        #expect(result.contains("42.0"))
    }
}

// MARK: - buildFoundationModelsPrompt helper tests

@Suite("buildFoundationModelsPrompt helper")
struct BuildFoundationModelsPromptTests {

    @available(iOS 26.0, macOS 26.0, *)
    @Test("prompt contains OCR text")
    func promptContainsOCRText() {
        let ocrText = "Total: $42.00\nStore: Whole Foods Market"
        let result = buildFoundationModelsPrompt(ocrText: ocrText, schemaPrompt: "schema here")
        #expect(result.contains("Total: $42.00"))
        #expect(result.contains("Whole Foods Market"))
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("prompt contains schema prompt")
    func promptContainsSchemaPrompt() {
        let schemaPrompt = "Extract JSON with fields: storeName, total"
        let result = buildFoundationModelsPrompt(ocrText: "some text", schemaPrompt: schemaPrompt)
        #expect(result.contains(schemaPrompt))
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("prompt instructs JSON-only response")
    func promptInstructsJSONOnlyResponse() {
        let result = buildFoundationModelsPrompt(ocrText: "text", schemaPrompt: "schema")
        // Must include instruction to respond with only JSON
        #expect(result.lowercased().contains("json"))
        #expect(result.contains("{") || result.contains("JSON"))
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("empty OCR text is valid input — prompt still constructed")
    func emptyOCRTextIsValid() {
        let result = buildFoundationModelsPrompt(ocrText: "", schemaPrompt: "schema")
        #expect(!result.isEmpty)
        #expect(result.contains("schema"))
    }
}

// MARK: - appleFoundationModels retry logic tests (via testable seam)

@Suite("appleFoundationModels retry logic")
struct AppleFMRetryLogicTests {

    private struct Doc: Decodable { let title: String? }

    /// Helper: loads a real fixture JPEG large enough for Vision OCR (> 2x2 pixels required).
    /// Uses the supermarket-receipt fixture from the test bundle since Vision framework
    /// rejects images with dimensions ≤ 2 pixels in any dimension.
    private func fixtureJPEGData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "supermarket-receipt", withExtension: "jpg",
                                          subdirectory: "Fixtures") else {
            throw IrisError.imageUnreadable(reason: "Fixture not found: supermarket-receipt.jpg")
        }
        return try Data(contentsOf: url)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("valid JSON on first attempt succeeds immediately")
    func validJSONOnFirstAttemptSucceeds() async throws {
        let provider = IrisProvider._appleFoundationModels(maxRetries: 3) { _ in
            return #"{"title": "Whole Foods Market"}"#
        }
        let iris = IrisClient(provider: provider)
        let result = try await iris.parse(data: try fixtureJPEGData(), mimeType: "image/jpeg", as: Doc.self)
        #expect(result.title == "Whole Foods Market")
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("invalid JSON on first attempt, valid on second — retry succeeds")
    func retriesOnInvalidJSON() async throws {
        let attemptBox = CaptureBox<Int>()
        let provider = IrisProvider._appleFoundationModels(maxRetries: 3) { _ in
            let attempt = (await attemptBox.get() ?? 0) + 1
            await attemptBox.set(attempt)
            if attempt == 1 { return "not valid json at all" }
            return #"{"title": "Retry Success"}"#
        }
        let iris = IrisClient(provider: provider)
        let result = try await iris.parse(data: try fixtureJPEGData(), mimeType: "image/jpeg", as: Doc.self)
        #expect(result.title == "Retry Success")
        #expect(await attemptBox.get() == 2)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("all retries exhausted throws modelFailure")
    func allRetriesExhaustedThrowsModelFailure() async throws {
        let jpeg = try fixtureJPEGData()
        let provider = IrisProvider._appleFoundationModels(maxRetries: 3) { _ in
            return "this is never valid JSON no matter how many times you try"
        }
        let iris = IrisClient(provider: provider)
        var caught: (any Error)?
        do {
            _ = try await iris.parse(data: jpeg, mimeType: "image/jpeg", as: Doc.self)
        } catch {
            caught = error
        }
        if case .modelFailure(let message) = caught as? IrisError {
            #expect(message.contains("3")) // mentions attempt count
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("session error maps to modelFailure (not raw error escape)")
    func sessionErrorMapsToModelFailure() async throws {
        let jpeg = try fixtureJPEGData()
        let provider = IrisProvider._appleFoundationModels(maxRetries: 3) { _ in
            throw URLError(.badServerResponse) // any error simulates FM session failure
        }
        let iris = IrisClient(provider: provider)
        var caught: (any Error)?
        do {
            _ = try await iris.parse(data: jpeg, mimeType: "image/jpeg", as: Doc.self)
        } catch {
            caught = error
        }
        // Must be IrisError.modelFailure — raw error must NOT escape
        if case .modelFailure = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
        // Raw URLError must NOT propagate
        #expect(!(caught is URLError))
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("JSON wrapped in code fence is accepted as valid")
    func jsonInCodeFenceIsAccepted() async throws {
        let provider = IrisProvider._appleFoundationModels(maxRetries: 3) { _ in
            return """
            ```json
            {"title": "Receipt from Whole Foods Market"}
            ```
            """
        }
        let iris = IrisClient(provider: provider)
        let result = try await iris.parse(data: try fixtureJPEGData(), mimeType: "image/jpeg", as: Doc.self)
        #expect(result.title == "Receipt from Whole Foods Market")
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("maxRetries=1 — no retry on invalid JSON, throws immediately")
    func maxRetriesOne_noRetryOnInvalidJSON() async throws {
        let jpeg = try fixtureJPEGData()
        let callCount = CaptureBox<Int>()
        let provider = IrisProvider._appleFoundationModels(maxRetries: 1) { _ in
            await callCount.set((await callCount.get() ?? 0) + 1)
            return "not json"
        }
        let iris = IrisClient(provider: provider)
        var caught: (any Error)?
        do {
            _ = try await iris.parse(data: jpeg, mimeType: "image/jpeg", as: Doc.self)
        } catch {
            caught = error
        }
        if case .modelFailure = caught as? IrisError {
            #expect(await callCount.get() == 1) // exactly one attempt, no retry
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }
}

#endif // canImport(FoundationModels)

// MARK: - Shared actor helper

private actor CaptureBox<T> {
    private var value: T?
    func set(_ v: T) { value = v }
    func get() -> T? { value }
}
