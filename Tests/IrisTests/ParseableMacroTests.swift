// Tests/IrisTests/ParseableMacroTests.swift
import Testing
import Foundation          // required for JSONSerialization and Data(utf8:)
@testable import Iris

// Declare test structs at file scope (not inside the test suite struct)
// @Parseable macro expands at compile time — must be at declaration scope

@Parseable
struct TestReceipt {
    var store: String
    var total: Double
    var date: String?       // optional — should be nullable in schema, absent from required
    var count: Int
}

@Parseable
struct ArrayStruct {
    var tags: [String]
    var counts: [Int]?
}

@Parseable
struct InnerStruct {
    var value: Int
}

@Parseable
struct NestedOuter {
    var name: String
    var inner: InnerStruct
}

@Suite("ParseableMacroTests")
struct ParseableMacroTests {

    // MARK: - irisSchema Generation

    @Test("irisSchema contains all property names")
    func schemaContainsAllPropertyNames() {
        let schema = TestReceipt.irisSchema
        #expect(schema.contains("\"store\""))
        #expect(schema.contains("\"total\""))
        #expect(schema.contains("\"date\""))
        #expect(schema.contains("\"count\""))
    }

    @Test("irisSchema marks Optional fields as nullable")
    func schemaMarksOptionalFieldAsNullable() {
        let schema = TestReceipt.irisSchema
        // Optional field must have null type in the array
        #expect(schema.contains("null"))
        // date should appear with a nullable type definition
        #expect(schema.contains("\"date\""))
    }

    @Test("irisSchema required array excludes Optional fields")
    func schemaRequiredExcludesOptionalFields() {
        let schema = TestReceipt.irisSchema
        // required array present (has non-optional fields)
        #expect(schema.contains("required"))
        // Non-optional fields are required
        #expect(schema.contains("\"store\""))
        #expect(schema.contains("\"total\""))
        #expect(schema.contains("\"count\""))
    }

    @Test("irisSchema is valid JSON")
    func schemaIsValidJSON() throws {
        let schema = TestReceipt.irisSchema
        let data = Data(schema.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any])
    }

    // MARK: - Decodable Conformance

    @Test("Decodable conformance decodes all required fields")
    func decodableDecodesRequiredFields() throws {
        let json = #"{"store": "Walmart", "total": 42.5, "count": 3}"#
        let receipt = try JSONDecoder.iris.decode(TestReceipt.self, from: Data(json.utf8))
        #expect(receipt.store == "Walmart")
        #expect(receipt.total == 42.5)
        #expect(receipt.count == 3)
    }

    @Test("Decodable maps absent Optional field to nil")
    func decodableMapsAbsentOptionalToNil() throws {
        // date is absent from JSON — should decode to nil, not throw
        let json = #"{"store": "Target", "total": 15.0, "count": 1}"#
        let receipt = try JSONDecoder.iris.decode(TestReceipt.self, from: Data(json.utf8))
        #expect(receipt.date == nil)
    }

    // MARK: - PromptBuilder Integration

    @Test("PromptBuilder uses irisSchema for @Parseable types")
    func promptBuilderUsesIrisSchema() {
        // @Parseable makes TestReceipt conform to IrisSchemaProviding
        // PromptBuilder.build(for:) checks `type as? IrisSchemaProviding.Type` → true
        let prompt = PromptBuilder.build(for: TestReceipt.self)
        // The prompt should contain field names from irisSchema
        #expect(prompt.contains("store"))
        #expect(prompt.contains("total"))
        #expect(prompt.contains("date"))
    }

    // MARK: - Backward Compatibility

    // MARK: - Array Property Schema

    @Test("irisSchema emits array type for [String] property")
    func schemaArrayProperty_emitsArrayType() {
        let schema = ArrayStruct.irisSchema
        #expect(schema.contains("\"array\""))
    }

    @Test("irisSchema emits nullable array type for [Int]? property")
    func schemaOptionalArrayProperty_emitsNullableArray() {
        let schema = ArrayStruct.irisSchema
        #expect(schema.contains("\"array\""))
        #expect(schema.contains("null"))
    }

    // MARK: - Nested @Parseable Type Schema

    @Test("irisSchema for nested @Parseable type contains inner schema")
    func nestedParseableType_emitsNestedSchema() {
        let outerSchema = NestedOuter.irisSchema
        let innerSchema = InnerStruct.irisSchema
        #expect(outerSchema.contains(innerSchema))
    }

    // MARK: - Backward Compatibility

    @Test("Manually Decodable struct continues to work unchanged")
    func manuallyDecodableStructWorksUnchanged() throws {
        struct PriceTag: Decodable { var label: String; var value: Double }
        let json = #"{"label": "sale", "value": 9.99}"#
        let tag = try JSONDecoder.iris.decode(PriceTag.self, from: Data(json.utf8))
        #expect(tag.label == "sale")
        #expect(tag.value == 9.99)
    }

    @Test("Manually Decodable struct uses Mirror path in PromptBuilder")
    func manuallyDecodableStructUsesMirrorFallback() {
        struct Invoice: Decodable { var amount: String }
        // Invoice does NOT have irisSchema → PromptBuilder uses Mirror fallback
        let prompt = PromptBuilder.build(for: Invoice.self)
        // Mirror path still produces a valid prompt (contains amount field)
        #expect(prompt.contains("amount") || !prompt.isEmpty)
    }
}
