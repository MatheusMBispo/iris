import Foundation
import Testing
@testable import Iris

@Suite("IrisClient")
struct IrisClientTests {
    @Test("public API stubs are accessible")
    func publicAPIStubsAreAccessible() {
        let client = IrisClient()
        let model = IrisModel.claude

        #expect(String(describing: type(of: client)) == "IrisClient")
        #expect(String(describing: type(of: model)) == "IrisModel")
        #expect(String(describing: IrisError.self) == "IrisError")
    }
}

@Suite("IrisError public shape")
struct IrisErrorTests {
    @Test("IrisError has exactly 5 cases with correct associated values")
    func errorCases() {
        let imageErr = IrisError.imageUnreadable(reason: "bad pixel")
        let modelErr = IrisError.modelFailure(message: "timeout")
        let decodeErr = IrisError.decodingFailed(raw: "{}")
        let netErr = IrisError.networkError(underlying: URLError(.badURL))
        let apiErr = IrisError.invalidAPIKey

        #expect(String(describing: imageErr).contains("imageUnreadable"))
        #expect(String(describing: modelErr).contains("modelFailure"))
        #expect(String(describing: decodeErr).contains("decodingFailed"))
        #expect(String(describing: netErr).contains("networkError"))
        #expect(String(describing: apiErr) == "invalidAPIKey")
    }
}

@Suite("IrisModel public shape")
struct IrisModelTests {
    @Test("IrisModel.claude stub throws modelFailure")
    func claudeStubThrows() async {
        let model = IrisModel.claude
        var caughtError: (any Error)?
        do {
            _ = try await model.parse(Data(), "test")
        } catch {
            caughtError = error
        }
        #expect(caughtError is IrisError)
        if case .modelFailure = caughtError as? IrisError {
            // correct — stub throws modelFailure as expected
        } else {
            Issue.record("Expected IrisError.modelFailure but got: \(String(describing: caughtError))")
        }
    }

    @Test("IrisModel can be created with custom parse closure")
    func customModelCreation() async throws {
        let model = IrisModel { _, _ in "response" }
        let result = try await model.parse(Data(), "prompt")
        #expect(result == "response")
    }
}

@Suite("IrisDebugInfo public shape")
struct IrisDebugInfoTests {
    @Test("IrisDebugInfo stores ocrText and rawJSON")
    func fieldsAreStored() {
        let info = IrisDebugInfo(ocrText: "hello world", rawJSON: #"{"text":"hello"}"#)
        #expect(info.ocrText == "hello world")
        #expect(info.rawJSON == #"{"text":"hello"}"#)
    }
}
