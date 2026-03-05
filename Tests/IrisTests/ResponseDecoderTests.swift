import Testing
import Foundation
@testable import Iris

@Suite("ResponseDecoder")
struct ResponseDecoderTests {

    private struct SampleStruct: Decodable {
        let firstName: String
        let age: Int?
    }

    @Test("decode valid JSON returns struct")
    func decode_validJSON_returnsStruct() throws {
        let json = #"{"first_name": "Ana", "age": 30}"#
        let result = try ResponseDecoder.decode(SampleStruct.self, from: json)
        #expect(result.firstName == "Ana")
        #expect(result.age == 30)
    }

    @Test("decode JSON with missing optional field returns nil for that field")
    func decode_missingOptionalField_isNil() throws {
        let json = #"{"first_name": "Bob"}"#
        let result = try ResponseDecoder.decode(SampleStruct.self, from: json)
        #expect(result.firstName == "Bob")
        #expect(result.age == nil)
    }

    @Test("decode invalid JSON throws decodingFailed with raw string preserved")
    func decode_invalidJSON_throwsDecodingFailed() {
        let badJSON = "{ invalid }"
        do {
            _ = try ResponseDecoder.decode(SampleStruct.self, from: badJSON)
            Issue.record("Expected throw but function returned normally")
        } catch IrisError.decodingFailed(let raw) {
            #expect(raw == badJSON)
        } catch {
            Issue.record("Expected IrisError.decodingFailed, got: \(error)")
        }
    }

    @Test("decode type mismatch throws decodingFailed (no raw DecodingError escapes)")
    func decode_typeMismatch_throwsDecodingFailed() {
        let json = #"{"first_name": 123}"#  // firstName expects String, gets Int
        do {
            _ = try ResponseDecoder.decode(SampleStruct.self, from: json)
            Issue.record("Expected throw but function returned normally")
        } catch IrisError.decodingFailed {
            // expected
        } catch {
            Issue.record("Expected IrisError.decodingFailed, got: \(error)")
        }
    }

    @Test("JSONDecoder.iris uses convertFromSnakeCase strategy")
    func irisDecoder_usesSnakeCaseStrategy() throws {
        let json = #"{"first_name": "Carlos"}"#
        let result = try JSONDecoder.iris.decode(SampleStruct.self, from: json.data(using: .utf8)!)
        #expect(result.firstName == "Carlos")
    }
}
