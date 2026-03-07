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

    // MARK: - @Parseable Integration Tests (Strategy 1)

    @Test("@Parseable struct uses irisSchema path — prompt contains typed integer")
    func parseableStructUsesIrisSchemaPath() {
        let prompt = PromptBuilder.build(for: TypedParseableReceipt.self)
        // "integer" is the discriminating signal: Mirror ALWAYS produces "string" for Int.
        // Its presence in the prompt proves Strategy 1 (irisSchema) was used.
        #expect(prompt.contains("\"integer\""))
    }

    @Test("@Parseable prompt contains all typed JSON Schema types")
    func parseablePromptContainsAllTypedFields() {
        let prompt = PromptBuilder.build(for: TypedParseableReceipt.self)
        #expect(prompt.contains("\"integer\""))  // count: Int
        #expect(prompt.contains("\"number\""))   // total: Double
        #expect(prompt.contains("\"boolean\""))  // isPaid: Bool
    }

    @Test("Mirror fallback produces valid prompt for plain Decodable")
    func mirrorFallbackProducesValidPrompt() {
        // MixedReceipt is plain Decodable (no @Parseable) → goes through Mirror Strategy 2
        let prompt = PromptBuilder.build(for: MixedReceipt.self)
        #expect(!prompt.isEmpty)
        // Mirror produces "string" for all fields — no "integer", "number", "boolean"
        #expect(prompt.contains("\"string\""))
        #expect(prompt.contains("invoiceNumber"))
    }

    // MARK: - Mirror Type Inference Tests (PROMPT-01) and Dictionary Placeholder Tests (PROMPT-02)

    private struct PrimitiveMirrorReceipt: Decodable {
        var count: Int
        var total: Double
        var isPaid: Bool
        var note: String?
    }

    private struct DictReceipt: Decodable {
        var metadata: [String: String]
    }

    @Test func schemaFromMirror_intField_emitsInteger() {
        let prompt = PromptBuilder.build(for: PrimitiveMirrorReceipt.self)
        #expect(prompt.contains("\"integer\""))
    }

    @Test func schemaFromMirror_doubleField_emitsNumber() {
        let prompt = PromptBuilder.build(for: PrimitiveMirrorReceipt.self)
        #expect(prompt.contains("\"number\""))
    }

    @Test func schemaFromMirror_boolField_emitsBoolean() {
        let prompt = PromptBuilder.build(for: PrimitiveMirrorReceipt.self)
        #expect(prompt.contains("\"boolean\""))
    }

    @Test func placeholderValue_dictionaryField_doesNotCrash() {
        // If the dictionary branch is unreachable, buildPrototype will fail and
        // genericPrompt will be returned — still non-empty. After fix, Mirror path works.
        let prompt = PromptBuilder.build(for: DictReceipt.self)
        #expect(!prompt.isEmpty)
    }
}

// Declare at FILE SCOPE — NOT inside @Suite, NOT private.
// @Parseable macro expansion generates an extension at compile time;
// the struct must be at module declaration scope.
@Parseable
struct TypedParseableReceipt {
    var store: String
    var count: Int       // → "integer" in schema
    var total: Double    // → "number" in schema
    var isPaid: Bool     // → "boolean" in schema
    var date: String?    // → nullable ["string","null"] in schema
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
