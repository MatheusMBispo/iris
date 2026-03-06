import Foundation
import Testing
@testable import Iris

@Suite("IrisProvider.openAI", .serialized)
struct OpenAIProviderTests {

    // MARK: - Mock Response Bodies

    private let openAISuccessJSON = """
    {"choices":[{"message":{"content":"{}"}}]}
    """.data(using: .utf8)!

    private let openAIEmptyChoicesJSON = """
    {"choices":[]}
    """.data(using: .utf8)!

    // MARK: - Tests

    @Test func successfulParse() async throws {
        let session = await makeMockSession { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, openAISuccessJSON)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        let result = try await provider.parse(minimalJPEGData(), "test prompt")
        #expect(result == "{}")
    }

    @Test func http401ThrowsInvalidAPIKey() async throws {
        let session = await makeMockSession { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let provider = IrisProvider.openAI(apiKey: "bad-key", model: "gpt-4o", session: session)
        var caught: (any Error)?
        do {
            _ = try await provider.parse(minimalJPEGData(), "test prompt")
        } catch {
            caught = error
        }
        if case .invalidAPIKey = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.invalidAPIKey, got: \(String(describing: caught))")
        }
    }

    @Test func http500ThrowsModelFailure() async throws {
        let session = await makeMockSession { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        var caught: (any Error)?
        do {
            _ = try await provider.parse(minimalJPEGData(), "test prompt")
        } catch {
            caught = error
        }
        if case .modelFailure = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }

    @Test func urlErrorThrowsNetworkError() async throws {
        let session = await makeMockSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        var caught: (any Error)?
        do {
            _ = try await provider.parse(minimalJPEGData(), "test prompt")
        } catch {
            caught = error
        }
        if case .networkError = caught as? IrisError {
            // expected
        } else {
            Issue.record("Expected IrisError.networkError, got: \(String(describing: caught))")
        }
    }

    @Test func emptyChoicesThrowsModelFailure() async throws {
        let session = await makeMockSession { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, openAIEmptyChoicesJSON)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        var caught: (any Error)?
        do {
            _ = try await provider.parse(minimalJPEGData(), "test prompt")
        } catch {
            caught = error
        }
        if case .modelFailure(let message) = caught as? IrisError {
            #expect(message.contains("No choices"))
        } else {
            Issue.record("Expected IrisError.modelFailure, got: \(String(describing: caught))")
        }
    }

    @Test func requestBodyContainsBase64ImageAndModel() async throws {
        var capturedRequest: URLRequest?
        let imageData = minimalJPEGData()
        let session = await makeMockSession { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, openAISuccessJSON)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        _ = try await provider.parse(imageData, "test prompt")

        let body = bodyData(from: capturedRequest!)
        #expect(body != nil)
        let bodyString = String(data: body!, encoding: .utf8)!
        // JSONEncoder escapes forward slashes (/ → \/), normalize before comparing base64
        let normalizedBody = bodyString.replacingOccurrences(of: "\\/", with: "/")
        #expect(normalizedBody.contains(imageData.base64EncodedString()))
        #expect(normalizedBody.contains("gpt-4o"))
    }

    @Test func proseWrappedQuotedNumberIsNormalized() async throws {
        let content = "Here is the JSON:\n```json\n{\"storeName\":\"Fresh Market\",\"totalAmount\":\"$45.78\"}\n```"
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
        let session = await makeMockSession { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseBody)
        }
        let provider = IrisProvider.openAI(apiKey: "sk-test", model: "gpt-4o", session: session)
        let result = try await provider.parse(minimalJPEGData(), PromptBuilder.build(for: OpenAITypedReceipt.self))
        let data = try #require(result.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["storeName"] as? String == "Fresh Market")
        #expect((object["totalAmount"] as? NSNumber)?.doubleValue == 45.78)
    }
}

@Parseable
struct OpenAITypedReceipt {
    let storeName: String?
    let totalAmount: Double?
}

// MARK: - Test Helpers (Mirrored from IrisClientTests.swift — local private copies)

private actor HandlerStorage {
    var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
}

private final class OpenAIMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let storage = HandlerStorage()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let req = request
        let cli = client
        Task {
            let h = await OpenAIMockURLProtocol.storage.handler
            guard let handler = h else {
                cli?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            do {
                let (response, data) = try handler(req)
                cli?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                cli?.urlProtocol(self, didLoad: data)
                cli?.urlProtocolDidFinishLoading(self)
            } catch {
                cli?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private func makeMockSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) async -> URLSession {
    await OpenAIMockURLProtocol.storage.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OpenAIMockURLProtocol.self]
    return URLSession(configuration: config)
}

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

// MARK: - minimalJPEGData — Mirrored from IrisClientTests.swift lines 735–767
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
