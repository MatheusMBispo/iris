import Foundation
import Testing
@testable import Iris

@Suite("IrisClient")
struct IrisClientTests {
    @Test("public API stubs are accessible")
    func publicAPIStubsAreAccessible() {
        let client = IrisClient()
        let model = IrisModel.claude(apiKey: "test")

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

@Suite("IrisModel public shape")
struct IrisModelTests {
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

// MARK: - IrisModel.claude URLSession behavior

@Suite("IrisModel.claude URLSession behavior", .serialized)
struct IrisModelClaudeTests {

    @Test func claude_sendsCorrectHeaders() async throws {
        var capturedRequest: URLRequest?
        let session = makeMockSession { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"content":[{"type":"text","text":"{}"}]}"#.data(using: .utf8)!
            return (response, body)
        }
        let model = IrisModel.claude(apiKey: "test-key", session: session)
        _ = try await model.parse(Data(), "prompt")
        #expect(capturedRequest?.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(capturedRequest?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func claude_sendsBase64Image() async throws {
        let imageData = Data([0xAA, 0xBB, 0xCC])
        var requestBody: [String: Any]?
        let session = makeMockSession { request in
            // URLSession converts httpBody → httpBodyStream when going through URLProtocol
            if let body = bodyData(from: request) {
                requestBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let responseBody = #"{"content":[{"type":"text","text":"{}"}]}"#.data(using: .utf8)!
            return (response, responseBody)
        }
        let model = IrisModel.claude(apiKey: "key", session: session)
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
        let model = IrisModel.claude(apiKey: "key", session: session)
        let result = try await model.parse(Data(), "prompt")
        #expect(result == expectedJSON)
    }

    @Test func claude_http401_throwsInvalidAPIKey() async {
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let model = IrisModel.claude(apiKey: "bad-key", session: session)
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
        let model = IrisModel.claude(apiKey: "key", session: session)
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
        let model = IrisModel.claude(apiKey: "key", session: session)
        var caught: (any Error)?
        do { _ = try await model.parse(Data(), "prompt") } catch { caught = error }
        if case .networkError(let underlying) = caught as? IrisError {
            #expect(underlying is URLError)
        } else {
            Issue.record("Expected IrisError.networkError, got: \(String(describing: caught))")
        }
    }
}

// MARK: - Test Helpers

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
