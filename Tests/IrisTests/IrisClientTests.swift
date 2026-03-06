import Foundation
import Testing
@testable import Iris
#if canImport(Darwin)
import Darwin
#endif

// MARK: - IrisError shape tests

@Suite("IrisError public shape")
struct IrisErrorTests {
    @Test("IrisError has exactly 5 cases with correct associated values")
    func errorCases() {
        let imageErr = IrisError.imageUnreadable(reason: "bad pixel")
        let modelErr = IrisError.modelFailure(message: "timeout")
        let decodeErr = IrisError.decodingFailed(raw: "{}")
        let netErr = IrisError.networkError(underlying: URLError(.badURL))
        let apiErr = IrisError.invalidAPIKey

        if case .imageUnreadable(let reason) = imageErr {
            #expect(reason == "bad pixel")
        } else {
            Issue.record("Expected .imageUnreadable(reason:)")
        }

        if case .modelFailure(let message) = modelErr {
            #expect(message == "timeout")
        } else {
            Issue.record("Expected .modelFailure(message:)")
        }

        if case .decodingFailed(let raw) = decodeErr {
            #expect(raw == "{}")
        } else {
            Issue.record("Expected .decodingFailed(raw:)")
        }

        if case .networkError(let underlying) = netErr {
            #expect(underlying is URLError)
        } else {
            Issue.record("Expected .networkError(underlying:)")
        }

        if case .invalidAPIKey = apiErr {
            // expected
        } else {
            Issue.record("Expected .invalidAPIKey")
        }
    }
}

// MARK: - IrisProvider shape tests

@Suite("IrisProvider public shape")
struct IrisProviderTests {
    @Test("IrisProvider can be created with custom parse closure")
    func customProviderCreation() async throws {
        let model = IrisProvider { _, _ in "response" }
        let result = try await model.parse(Data(), "prompt")
        #expect(result == "response")
    }
}

// MARK: - IrisProvider.mock tests

@Suite("IrisProvider.mock")
struct IrisProviderMockTests {
    private struct OptionalReceipt: Decodable {
        let merchant: String?
        let total: Double?
        let date: String?
    }

    @Test("mock returns empty JSON object without network call")
    func mockReturnsEmptyJSON() async throws {
        let result = try await IrisProvider.mock.parse(Data(), "test prompt")
        #expect(result == "{}")
    }

    @Test("mock decodes into all-Optional struct producing all-nil values")
    func mockDecodesIntoAllOptionalStruct() async throws {
        let iris = IrisClient(provider: .mock)
        let receipt = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: OptionalReceipt.self)
        #expect(receipt.merchant == nil)
        #expect(receipt.total == nil)
        #expect(receipt.date == nil)
    }
}

// MARK: - Custom provider injection tests

@Suite("Custom Provider Injection")
struct CustomModelInjectionTests {
    private struct LabelInfo: Decodable {
        let label: String
    }

    private struct ValueInfo: Decodable {
        let value: Int
    }

    private struct Doc: Decodable {
        let title: String?
    }

    @Test("init(provider:) uses provided provider instead of claude")
    func initProviderUsesProvidedProvider() async throws {
        let customModel = IrisProvider { _, _ in #"{"label":"injected"}"# }
        let iris = IrisClient(provider: customModel)
        let result = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: LabelInfo.self)
        #expect(result.label == "injected")
    }

    @Test("init(apiKey:provider:) uses provided provider, ignores apiKey for calls")
    func initAPIKeyProviderUsesProvidedProvider() async throws {
        let customModel = IrisProvider { _, _ in #"{"value":42}"# }
        let iris = IrisClient(apiKey: "unused-key", provider: customModel)
        let result = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: ValueInfo.self)
        #expect(result.value == 42)
    }

    @Test("custom provider closure receives normalized imageData and prompt")
    func customProviderReceivesCorrectArguments() async throws {
        let dataBox = CaptureBox<Data>()
        let promptBox = CaptureBox<String>()

        let customModel = IrisProvider { data, prompt in
            await dataBox.set(data)
            await promptBox.set(prompt)
            return "{}"
        }

        let iris = IrisClient(provider: customModel)
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Doc.self)

        let capturedData = await dataBox.get()
        let capturedPrompt = await promptBox.get()
        #expect(capturedData != nil)
        #expect(capturedData?.starts(with: [0xFF, 0xD8]) == true)
        #expect(capturedPrompt != nil)
    }

    @Test("parse call syntax is identical regardless of provider used")
    func parseSyntaxUnchanged() async throws {
        let mockIris = IrisClient(provider: .mock)
        let customIris = IrisClient(provider: IrisProvider { _, _ in "{}" })
        let apiKeyMockIris = IrisClient(apiKey: "fake-key", provider: .mock)

        _ = try await mockIris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Doc.self)
        _ = try await customIris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Doc.self)
        _ = try await apiKeyMockIris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Doc.self)
    }
}

// MARK: - IrisDebugInfo shape tests

@Suite("IrisDebugInfo public shape")
struct IrisDebugInfoTests {
    @Test("IrisDebugInfo stores ocrText and rawJSON")
    func fieldsAreStored() {
        let info = IrisDebugInfo(ocrText: "hello world", rawJSON: #"{"text":"hello"}"#)
        #expect(info.ocrText == "hello world")
        #expect(info.rawJSON == #"{"text":"hello"}"#)
    }
}

// MARK: - IrisProvider.claude URLSession behavior

@Suite("IrisProvider.claude URLSession behavior", .serialized)
struct IrisProviderClaudeURLSessionTests {

    @Test func claude_sendsCorrectHeaders() async throws {
        var capturedRequest: URLRequest?
        let session = makeMockSession { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"content":[{"type":"text","text":"{}"}]}"#.data(using: .utf8)!
            return (response, body)
        }
        let model = IrisProvider.claude(apiKey: "test-key", model: "claude-opus-4-6", session: session)
        _ = try await model.parse(Data(), "prompt")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(capturedRequest?.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(capturedRequest?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func claude_sendsBase64Image() async throws {
        let imageData = Data([0xAA, 0xBB, 0xCC])
        var requestBody: [String: Any]?
        let session = makeMockSession { request in
            if let body = bodyData(from: request) {
                requestBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let responseBody = #"{"content":[{"type":"text","text":"{}"}]}"#.data(using: .utf8)!
            return (response, responseBody)
        }
        let model = IrisProvider.claude(apiKey: "key", model: "claude-opus-4-6", session: session)
        _ = try await model.parse(imageData, "prompt")
        let messages = requestBody?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        let imageBlock = content?.first(where: { $0["type"] as? String == "image" })
        let source = imageBlock?["source"] as? [String: Any]
        #expect(source?["type"] as? String == "base64")
        #expect(source?["media_type"] as? String == "image/jpeg")
        #expect(source?["data"] as? String == imageData.base64EncodedString())
    }

    @Test func claude_returnsFirstTextBlock() async throws {
        let expectedJSON = #"{"total":"R$42.00"}"#
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"content\":[{\"type\":\"text\",\"text\":\"\(expectedJSON.replacingOccurrences(of: "\"", with: "\\\""))\"}]}".data(using: .utf8)!
            return (response, body)
        }
        let model = IrisProvider.claude(apiKey: "key", model: "claude-opus-4-6", session: session)
        let result = try await model.parse(Data(), "prompt")
        #expect(result == expectedJSON)
    }

    @Test func claude_normalizesQuotedNumberFromWrappedJSON() async throws {
        let wrapped = "Here is the JSON:\n```json\n{\"storeName\":\"Fresh Market\",\"totalAmount\":\"$45.78\"}\n```"
        let body = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": wrapped]]
        ])
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        let model = IrisProvider.claude(apiKey: "key", model: "claude-opus-4-6", session: session)
        let result = try await model.parse(Data(), PromptBuilder.build(for: ClaudeTypedReceipt.self))
        let data = try #require(result.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["storeName"] as? String == "Fresh Market")
        #expect((object["totalAmount"] as? NSNumber)?.doubleValue == 45.78)
    }

    @Test func claude_http401_throwsInvalidAPIKey() async {
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let model = IrisProvider.claude(apiKey: "bad-key", model: "claude-opus-4-6", session: session)
        var caught: (any Error)?
        do { _ = try await model.parse(Data(), "prompt") } catch { caught = error }
        #expect(caught is IrisError)
        if case .invalidAPIKey = caught as? IrisError { /* expected */ } else {
            Issue.record("Expected IrisError.invalidAPIKey, got: \(String(describing: caught))")
        }
    }

    @Test func claude_httpError_throwsModelFailure() async {
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }
        let model = IrisProvider.claude(apiKey: "key", model: "claude-opus-4-6", session: session)
        var caught: (any Error)?
        do { _ = try await model.parse(Data(), "prompt") } catch { caught = error }
        if case .modelFailure(let message) = caught as? IrisError {
            #expect(message.contains("Internal Server Error"))
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }

    @Test func claude_urlError_throwsNetworkError() async {
        let session = makeMockSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let model = IrisProvider.claude(apiKey: "key", model: "claude-opus-4-6", session: session)
        var caught: (any Error)?
        do { _ = try await model.parse(Data(), "prompt") } catch { caught = error }
        if case .networkError(let underlying) = caught as? IrisError {
            #expect(underlying is URLError)
        } else {
            Issue.record("Expected IrisError.networkError, got: \(String(describing: caught))")
        }
    }
}

// MARK: - IrisClient behavior tests

@Suite("IrisClient behavior", .serialized)
struct IrisClientBehaviorTests {

    // Shared test structs

    private struct SimpleStruct: Decodable {
        let name: String
    }

    /// Tests snake_case decoding — `total_amount` JSON key maps to `totalAmount` Swift property.
    private struct SnakeCaseReceipt: Decodable {
        let totalAmount: String
        let vendorName: String?  // optional — used to verify nil mapping
    }

    // MARK: AC #1 — full pipeline executes in order

    @Test("parse(data:mimeType:as:) returns decoded struct via full pipeline")
    func parseData_fullPipeline_returnsDecodedStruct() async throws {
        let model = IrisProvider { _, _ in #"{"name": "iris"}"# }
        let client = IrisClient(provider: model)
        let result = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        #expect(result.name == "iris")
    }

    @Test("parse pipeline calls provider with prompt containing field names")
    func parsePipeline_providerReceivesPromptWithFieldNames() async throws {
        let capture = CaptureBox<String>()
        let model = IrisProvider { _, prompt in
            await capture.set(prompt)
            return #"{"total_amount": "R$1.00"}"#
        }
        let client = IrisClient(provider: model)
        _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SnakeCaseReceipt.self)
        // PromptBuilder ran and produced a prompt referencing the struct fields
        let prompt = await capture.get() ?? ""
        #expect(!prompt.isEmpty)
        #expect(prompt.contains("totalAmount") || prompt.contains("total_amount") || prompt.contains("vendorName") || prompt.contains("vendor_name"))
    }

    @Test("parse pipeline passes normalized JPEG data to provider (not raw input)")
    func parsePipeline_providerReceivesNormalizedData() async throws {
        let capture = CaptureBox<Data>()
        let model = IrisProvider { data, _ in
            await capture.set(data)
            return #"{"name": "test"}"#
        }
        let client = IrisClient(provider: model)
        _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        // Provider received data that is a valid JPEG (starts with FF D8)
        let capturedData = await capture.get()
        #expect(capturedData?.starts(with: [0xFF, 0xD8]) == true)
    }

    // MARK: AC #2 — optional field absent in JSON → nil

    @Test("optional field absent in provider JSON response decodes as nil")
    func optionalField_absentInJSON_isNil() async throws {
        // vendorName is absent from JSON → should decode as nil
        let model = IrisProvider { _, _ in #"{"total_amount": "R$42.00"}"# }
        let client = IrisClient(provider: model)
        let result = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SnakeCaseReceipt.self)
        #expect(result.totalAmount == "R$42.00")
        #expect(result.vendorName == nil)
    }

    // MARK: AC #3 — language-agnostic (same pipeline for any document language)

    @Test("pipeline works regardless of document content language")
    func pipeline_languageAgnostic() async throws {
        // Provider returns Portuguese values — pipeline must not break
        let model = IrisProvider { _, _ in #"{"name": "Supermercado"}"# }
        let client = IrisClient(provider: model)
        let result = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        #expect(result.name == "Supermercado")
    }

    // MARK: AC #4 — explicit-key and env-key init paths

    @Test("init(apiKey:) creates usable client without network calls in tests")
    func explicitKeyInit_createsClient() {
        let client = IrisClient(apiKey: "sk-test-key")
        #expect(String(describing: type(of: client)) == "IrisClient")
    }

    @Test("init(environment:) with missing key throws invalidAPIKey on parse (no network call)")
    func envKeyMissing_throwsInvalidAPIKey_withoutNetworkCall() async {
        let client = IrisClient(environment: [:])  // empty env — key is absent
        var caught: (any Error)?
        do {
            _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .invalidAPIKey = caught as? IrisError {
            // expected — no network call occurred
        } else {
            Issue.record("Expected IrisError.invalidAPIKey, got: \(String(describing: caught))")
        }
    }

    @Test("init(environment:) with valid key configures claude provider")
    func envKeyPresent_configuresProvider() async throws {
        // Use a mock provider to verify env-key path without real network calls
        // init(environment:) builds IrisProvider.claude internally; we verify via parse behavior
        // instead of testing IrisProvider.claude directly (covered in IrisProviderClaudeTests).
        // Since we can't inject a mock provider into init(environment:), we verify the init succeeds.
        let client = IrisClient(environment: ["ANTHROPIC_API_KEY": "sk-env-key"])
        #expect(String(describing: type(of: client)) == "IrisClient")
    }

    @Test("public init() with missing env key throws invalidAPIKey on parse")
    func publicInit_missingEnvKey_throwsInvalidAPIKey() async {
        await withEnvironmentValue("ANTHROPIC_API_KEY", nil) {
            let client = IrisClient()
            var caught: (any Error)?
            do {
                _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
            } catch {
                caught = error
            }
            if case .invalidAPIKey = caught as? IrisError {
                // expected
            } else {
                Issue.record("Expected IrisError.invalidAPIKey, got: \(String(describing: caught))")
            }
        }
    }

    @Test("public init() reads ANTHROPIC_API_KEY when present")
    func publicInit_readsEnvironmentKey() async {
        await withEnvironmentValue("ANTHROPIC_API_KEY", "sk-public-env") {
            let client = IrisClient()
            #expect(String(describing: type(of: client)) == "IrisClient")
        }
    }

    // MARK: AC #5 — overloads for all input forms

    @Test("parse(fileURL:as:) reads image file and returns decoded struct")
    func parseFileURL_returnsDecodedStruct() async throws {
        let model = IrisProvider { _, _ in #"{"name": "from-file"}"# }
        let client = IrisClient(provider: model)
        let url = try writeJPEGToTempFile(minimalJPEGData())
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await client.parse(fileURL: url, as: SimpleStruct.self)
        #expect(result.name == "from-file")
    }

    @Test("parse(fileURL:as:) throws imageUnreadable for missing file")
    func parseFileURL_missingFile_throwsImageUnreadable() async {
        let model = IrisProvider { _, _ in #"{"name": "x"}"# }
        let client = IrisClient(provider: model)
        let missingURL = URL(fileURLWithPath: "/tmp/iris_nonexistent_\(UUID().uuidString).jpg")
        var caught: (any Error)?
        do {
            _ = try await client.parse(fileURL: missingURL, as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .imageUnreadable = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.imageUnreadable, got: \(String(describing: caught))")
        }
    }

    // MARK: AC #6 — actor isolation, no DispatchQueue

    @Test("IrisClient is an actor type")
    func irisClientIsActor() {
        // Compile-time verification: IrisClient() is valid (actor init syntax)
        let client = IrisClient(apiKey: "test")
        _ = client  // actor reference — confirms it's an actor
        #expect(String(describing: type(of: client)) == "IrisClient")
    }

    // MARK: AC #7 — JSONDecoder.iris uses convertFromSnakeCase

    @Test("snake_case JSON key maps to camelCase Swift property via JSONDecoder.iris")
    func snakeCaseJSON_mapsToCamelCaseProperty() async throws {
        let model = IrisProvider { _, _ in #"{"total_amount": "R$99.99", "vendor_name": "Padaria"}"# }
        let client = IrisClient(provider: model)
        let result = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SnakeCaseReceipt.self)
        #expect(result.totalAmount == "R$99.99")
        #expect(result.vendorName == "Padaria")
    }

    // MARK: Error propagation boundaries (Tasks 3 + 4)

    @Test("invalid JSON from provider throws decodingFailed with raw JSON preserved")
    func invalidJSON_throwsDecodingFailed_withRawJSONPreserved() async throws {
        let badJSON = "not valid json at all"
        let model = IrisProvider { _, _ in badJSON }
        let client = IrisClient(provider: model)
        var caught: (any Error)?
        do {
            _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .decodingFailed(let raw) = caught as? IrisError {
            #expect(raw == badJSON)
        } else {
            Issue.record("Expected IrisError.decodingFailed, got: \(String(describing: caught))")
        }
    }

    @Test("type mismatch in JSON throws decodingFailed (no raw DecodingError escapes)")
    func typeMismatch_throwsDecodingFailed_notRawDecodingError() async throws {
        // `name` field is String but JSON provides an integer
        let model = IrisProvider { _, _ in #"{"name": 42}"# }
        let client = IrisClient(provider: model)
        var caught: (any Error)?
        do {
            _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .decodingFailed = caught as? IrisError {
            // expected — raw DecodingError was mapped to IrisError.decodingFailed
        } else {
            Issue.record("Expected IrisError.decodingFailed, got: \(String(describing: caught))")
        }
        // Confirm raw DecodingError did NOT escape
        #expect(!(caught is DecodingError))
    }

    @Test("imageUnreadable error from ImagePipeline propagates unchanged")
    func imageUnreadable_propagatesFromPipeline() async {
        let model = IrisProvider { _, _ in #"{"name": "x"}"# }
        let client = IrisClient(provider: model)
        var caught: (any Error)?
        do {
            _ = try await client.parse(data: Data([0x00, 0x01, 0x02]), mimeType: "image/jpeg", as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .imageUnreadable = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.imageUnreadable, got: \(String(describing: caught))")
        }
    }

    @Test("provider-layer networkError propagates unchanged")
    func networkError_propagatesFromProvider() async {
        let model = IrisProvider { _, _ in throw IrisError.networkError(underlying: URLError(.notConnectedToInternet)) }
        let client = IrisClient(provider: model)
        var caught: (any Error)?
        do {
            _ = try await client.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: SimpleStruct.self)
        } catch {
            caught = error
        }
        if case .networkError = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.networkError, got: \(String(describing: caught))")
        }
    }

    // MARK: Platform-gated NSImage overload (macOS only)

    #if canImport(AppKit) && !canImport(UIKit)
    @Test("parse(image: NSImage, as:) overload compiles and calls pipeline")
    func nsImageOverload_parsesSuccessfully() async throws {
        let model = IrisProvider { _, _ in #"{"name": "nsimage-test"}"# }
        let client = IrisClient(provider: model)
        let image = makeTestNSImage()
        let result = try await client.parse(image: image, as: SimpleStruct.self)
        #expect(result.name == "nsimage-test")
    }
    #endif

    #if canImport(UIKit)
    @Test("parse(image: UIImage, as:) overload compiles and calls pipeline")
    func uiImageOverload_parsesSuccessfully() async throws {
        let model = IrisProvider { _, _ in #"{"name": "uiimage-test"}"# }
        let client = IrisClient(provider: model)
        let image = makeTestUIImage()
        let result = try await client.parse(image: image, as: SimpleStruct.self)
        #expect(result.name == "uiimage-test")
    }
    #endif
}

// MARK: - Debug Mode Tests

@Suite("Debug Mode")
struct DebugModeTests {

    @Test("debugMode false (default): lastDebugInfo is nil after parse")
    func debugModeFalseLastDebugInfoIsNil() async throws {
        struct Receipt: Decodable { var total: Double? }
        let iris = IrisClient(provider: .mock)  // debugMode omitted → false
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info == nil)
    }

    @Test("debugMode true: lastDebugInfo is populated after successful parse")
    func debugModeTruePopulatesLastDebugInfo() async throws {
        struct Receipt: Decodable { var total: Double? }
        let iris = IrisClient(provider: .mock, debugMode: true)
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info != nil)
    }

    @Test("debugMode true: rawJSON contains the provider's raw output")
    func debugModeTrueRawJSONMatchesMockOutput() async throws {
        struct Receipt: Decodable { var total: Double? }
        let iris = IrisClient(provider: .mock, debugMode: true)  // mock returns "{}"
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info?.rawJSON == "{}")
    }

    @Test("debugMode true: ocrText equals rawJSON (single-pass vision provider)")
    func debugModeTrueOcrTextMatchesRawJSON() async throws {
        struct Receipt: Decodable { var total: Double? }
        let iris = IrisClient(provider: .mock, debugMode: true)
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info?.ocrText == info?.rawJSON)
    }

    @Test("debugMode true: lastDebugInfo captured even when decoding fails")
    func debugModeCapturedOnDecodingFailure() async throws {
        // Provider returns JSON with a required non-Optional field missing → decodingFailed
        struct StrictReceipt: Decodable { var merchant: String }  // non-Optional → fails on "{}"
        let customJSON = #"{"unexpected_field": "value"}"#
        let model = IrisProvider { _, _ in customJSON }
        let iris = IrisClient(provider: model, debugMode: true)
        do {
            _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: StrictReceipt.self)
            Issue.record("Expected decodingFailed to be thrown")
        } catch IrisError.decodingFailed(raw: _) {
            // Expected path — lastDebugInfo is captured BEFORE ResponseDecoder.decode throws
            let info = await iris.lastDebugInfo
            #expect(info != nil)
            #expect(info?.rawJSON == customJSON)
        }
    }

    @Test("debugMode true: subsequent parse overwrites lastDebugInfo")
    func debugModeSubsequentParseUpdatesLastDebugInfo() async throws {
        struct Receipt: Decodable { var total: Double? }
        let firstJSON = #"{"total": 9.90}"#
        let secondJSON = #"{"total": 42.0}"#
        let counter = CaptureBox<Int>()
        let model = IrisProvider { _, _ in
            let count = (await counter.get() ?? 0) + 1
            await counter.set(count)
            return count == 1 ? firstJSON : secondJSON
        }
        let iris = IrisClient(provider: model, debugMode: true)
        _ = try? await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        _ = try? await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info?.rawJSON == secondJSON)  // second call overwrites first
    }

    @Test("debugMode true: provider error updates lastDebugInfo with error details")
    func debugModeProviderErrorUpdatesLastDebugInfo() async throws {
        struct Receipt: Decodable { var total: Double? }
        // First call succeeds, second throws network error
        let firstJSON = #"{"total": 5.0}"#
        let counter = CaptureBox<Int>()
        let model = IrisProvider { _, _ in
            let count = (await counter.get() ?? 0) + 1
            await counter.set(count)
            if count == 1 { return firstJSON }
            throw IrisError.networkError(underlying: URLError(.notConnectedToInternet))
        }
        let iris = IrisClient(provider: model, debugMode: true)
        _ = try? await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        _ = try? await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        // After provider error: debug info reflects the latest failure details
        let info = await iris.lastDebugInfo
        #expect(info?.rawJSON != firstJSON)
        #expect(info?.rawJSON.isEmpty == false)
        #expect(info?.ocrText == info?.rawJSON)
    }

    @Test("debugMode true with init(apiKey:provider:debugMode:) variant")
    func debugModeViaApiKeyInit() async throws {
        // Verifies the apiKey init accepts debugMode
        struct Receipt: Decodable { var total: Double? }
        let iris = IrisClient(apiKey: "fake-key", provider: .mock, debugMode: true)
        _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
        let info = await iris.lastDebugInfo
        #expect(info != nil)
    }

    @Test("debugMode false with all init variants produces nil lastDebugInfo")
    func debugModeFalseAllInits() async throws {
        struct Receipt: Decodable { var total: Double? }
        // All three public variants without explicit debugMode
        let iris1 = IrisClient(provider: .mock)
        let iris2 = IrisClient(provider: .mock, retryPolicy: .none)
        let iris3 = IrisClient(apiKey: "key", provider: .mock)
        for iris in [iris1, iris2, iris3] {
            _ = try await iris.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
            let info = await iris.lastDebugInfo
            #expect(info == nil)
        }

        await withEnvironmentValue("ANTHROPIC_API_KEY", nil) {
            let envClient = IrisClient()
            _ = try? await envClient.parse(data: minimalJPEGData(), mimeType: "image/jpeg", as: Receipt.self)
            let envInfo = await envClient.lastDebugInfo
            #expect(envInfo == nil)
        }
    }
}

// MARK: - Test Helpers

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
    MockURLProtocol.requestHandler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Reads the HTTP body from a URLRequest, falling back to httpBodyStream when URLSession
/// converts httpBody to a stream (which happens when requests pass through URLProtocol).
private func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
    defer { buffer.deallocate(); stream.close() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 65_536)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

/// A valid 1×1 white JPEG (stable bytes, compatible with both UIKit and AppKit decoders).
private func minimalJPEGData() -> Data {
    let bytes: [UInt8] = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
        0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
        0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
        0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
        0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
        0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
        0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
        0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3F, 0x00, 0xFB, 0x26, 0xA2, 0x8A, 0xFF, 0xD9
    ]
    return Data(bytes)
}

private func writeJPEGToTempFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("iris_test_\(UUID().uuidString).jpg")
    try data.write(to: url)
    return url
}

private func withEnvironmentValue(_ key: String, _ value: String?, operation: () async -> Void) async {
    let previous = ProcessInfo.processInfo.environment[key]
    if let value {
        setenv(key, value, 1)
    } else {
        unsetenv(key)
    }

    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }

    await operation()
}

private actor CaptureBox<T> {
    private var value: T?

    func set(_ newValue: T) {
        value = newValue
    }

    func get() -> T? {
        value
    }
}

@Parseable
struct ClaudeTypedReceipt {
    let storeName: String?
    let totalAmount: Double?
}

#if canImport(AppKit) && !canImport(UIKit)
import AppKit

private func makeTestNSImage() -> NSImage {
    let size = NSSize(width: 1, height: 1)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}
#endif

#if canImport(UIKit)
import UIKit

private func makeTestUIImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    return renderer.image { context in
        context.cgContext.setFillColor(UIColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
#endif
