import Testing
import Foundation
@testable import Iris

@Suite("PromptBuilder")
struct PromptBuilderTests {

    // Test structs — local to test file only
    private struct SimpleReceipt: Decodable {
        let storeName: String?
        let total: String?
    }

    @Test func build_simpleStruct_containsFieldNames() {
        let prompt = PromptBuilder.build(for: SimpleReceipt.self)
        #expect(prompt.contains("storeName"))
        #expect(prompt.contains("total"))
    }

    @Test func build_optionalField_isNullableInSchema() {
        let prompt = PromptBuilder.build(for: SimpleReceipt.self)
        #expect(prompt.contains(#""storeName": {"type": ["string", "null"]}"#))
        #expect(prompt.contains(#""total": {"type": ["string", "null"]}"#))
    }

    @Test func build_languageAgnostic_noLanguageMentioned() {
        let prompt = PromptBuilder.build(for: SimpleReceipt.self)
        // Prompt must not constrain document language
        #expect(!prompt.lowercased().contains("english"))
        #expect(!prompt.lowercased().contains("portuguese"))
        #expect(!prompt.lowercased().contains("spanish"))
        // Must contain language-agnostic instruction
        #expect(prompt.contains("any language"))
    }

    @Test func build_irisSchemaProperty_usesStaticSchemaOverMirror() {
        let prompt = PromptBuilder.build(for: WithStaticSchema.self)
        #expect(prompt.contains("custom_schema_marker"))
    }

    @Test func build_nonOptionalField_isInRequiredArray() {
        let prompt = PromptBuilder.build(for: RequiredReceipt.self)
        #expect(prompt.contains("invoiceNumber"))
        #expect(prompt.contains("required"))
        #expect(prompt.contains(#""required": ["invoiceNumber"]"#))
    }

    @Test func build_allOptionalStruct_decodesEmptyJSON() {
        // All-optional struct: Mirror fallback should succeed via {} decode
        let prompt = PromptBuilder.build(for: SimpleReceipt.self)
        #expect(!prompt.isEmpty)
        // Should produce a structured schema, not just the generic fallback
        #expect(prompt.contains("storeName") || prompt.contains("total"))
    }

    @Test func build_promptInstructsReturnOnlyJSON() {
        let prompt = PromptBuilder.build(for: SimpleReceipt.self)
        #expect(prompt.contains("Return ONLY the JSON object, with no explanation or markdown formatting."))
    }

    @Test func build_requiredAndOptionalFields_areRepresentedCorrectly() {
        let prompt = PromptBuilder.build(for: MixedReceipt.self)
        #expect(prompt.contains(#""invoiceNumber": {"type": "string"}"#))
        #expect(prompt.contains(#""total": {"type": ["string", "null"]}"#))
        #expect(prompt.contains(#""required": ["invoiceNumber"]"#))
    }
}

// Test structs that conform to IrisSchemaProviding to test Strategy 1
private struct WithStaticSchema: Decodable, IrisSchemaProviding {
    let field: String?
    static var irisSchema: String { "{\"custom_schema_marker\": true}" }
}

private struct WithRequiredSchema: Decodable, IrisSchemaProviding {
    let invoiceNumber: String?
    static var irisSchema: String {
        "{\"type\":\"object\",\"properties\":{\"invoiceNumber\":{\"type\":\"string\"}},\"required\":[\"invoiceNumber\"]}"
    }
}

private struct RequiredReceipt: Decodable {
    let invoiceNumber: String
}

private struct MixedReceipt: Decodable {
    let invoiceNumber: String
    let total: String?
}
