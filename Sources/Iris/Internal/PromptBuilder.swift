import Foundation

enum PromptBuilder {

    // MARK: - Public Entry Point

    static func build<T: Decodable>(for type: T.Type) -> String {
        // Strategy 1: @Parseable-generated schema (compile-time, preferred — see Story 4.1)
        if let providing = type as? IrisSchemaProviding.Type {
            return formatPrompt(schema: providing.irisSchema)
        }
        // Strategy 2: Mirror reflection fallback (runtime, functional but no field descriptions)
        return buildViaMirror(for: type)
    }

    // MARK: - Strategy 2: Mirror Reflection

    private static func buildViaMirror<T: Decodable>(for type: T.Type) -> String {
        // Attempt to instantiate a prototype by decoding synthesized JSON.
        // This allows discovery of required keys via DecodingError and preserves
        // Mirror-based field extraction once we have a prototype instance.
        guard let result = buildPrototype(for: type) else {
            return genericPrompt(typeName: String(describing: type))
        }
        let mirror = Mirror(reflecting: result.prototype)
        let schema = schemaFromMirror(mirror, required: result.requiredKeys)
        return formatPrompt(schema: schema)
    }

    private static func schemaFromMirror(_ mirror: Mirror, required: Set<String>) -> String {
        var fields: [(name: String, nullable: Bool)] = []

        for child in mirror.children {
            guard let name = child.label else { continue }
            let childMirror = Mirror(reflecting: child.value)
            let isOptional = childMirror.displayStyle == .optional
            fields.append((name: name, nullable: isOptional))
        }

        var propertyLines: [String] = []
        for field in fields {
            if field.nullable {
                propertyLines.append("    \"\(field.name)\": {\"type\": [\"string\", \"null\"]}")
            } else {
                propertyLines.append("    \"\(field.name)\": {\"type\": \"string\"}")
            }
        }

        let requiredList = fields
            .map(\ .name)
            .filter { required.contains($0) }

        var schema = "{\n  \"type\": \"object\",\n  \"properties\": {\n"
        schema += propertyLines.joined(separator: ",\n")
        schema += "\n  }"

        if !requiredList.isEmpty {
            let requiredJSON = requiredList.map { "\"\($0)\"" }.joined(separator: ", ")
            schema += ",\n  \"required\": [\(requiredJSON)]"
        }

        schema += "\n}"
        return schema
    }

    private static func buildPrototype<T: Decodable>(for type: T.Type) -> (prototype: T, requiredKeys: Set<String>)? {
        var payload: [String: Any] = [:]
        var requiredKeys: Set<String> = []

        for _ in 0..<64 {
            guard JSONSerialization.isValidJSONObject(payload) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

            do {
                let prototype = try JSONDecoder().decode(type, from: data)
                return (prototype: prototype, requiredKeys: requiredKeys)
            } catch let DecodingError.keyNotFound(key, context) {
                requiredKeys.insert(key.stringValue)
                let path = context.codingPath + [key]
                setValue("", at: path)
                continue
            } catch let DecodingError.typeMismatch(expectedType, context) {
                guard let key = context.codingPath.last else { return nil }
                let value = placeholderValue(for: expectedType)
                setValue(value, at: context.codingPath)
                requiredKeys.insert(key.stringValue)
                continue
            } catch let DecodingError.valueNotFound(expectedType, context) {
                guard let key = context.codingPath.last else { return nil }
                let value = placeholderValue(for: expectedType)
                setValue(value, at: context.codingPath)
                requiredKeys.insert(key.stringValue)
                continue
            } catch {
                return nil
            }
        }

        return nil

        func setValue(_ value: Any, at path: [CodingKey]) {
            guard let last = path.last else { return }
            payload[last.stringValue] = value
        }
    }

    private static func placeholderValue(for type: Any.Type) -> Any {
        switch String(describing: type) {
        case "String", "Substring", "Character":
            return ""
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return 0
        case "Double", "Float", "CGFloat":
            return 0
        case "Bool":
            return false
        case "Date":
            return "1970-01-01T00:00:00Z"
        case "URL":
            return "https://example.com"
        default:
            let description = String(describing: type)
            if description.hasPrefix("Array<") || description.hasPrefix("[") {
                return []
            }
            if description.hasPrefix("Dictionary<") || description.hasPrefix("[") {
                return [:]
            }
            return ""
        }
    }

    // MARK: - Prompt Formatting

    private static func formatPrompt(schema: String) -> String {
        """
        Extract the data from this document image and return it as a JSON object matching the following schema.

        Schema:
        \(schema)

        Rules:
        - Return ONLY the JSON object, with no explanation or markdown formatting.
        - For optional fields not found in the document, use null.
        - The document may be in any language — extract values as they appear.
        """
    }

    private static func genericPrompt(typeName: String) -> String {
        """
        Extract all available data from this document image and return it as a JSON object for type \(typeName).

        Rules:
        - Return ONLY the JSON object, with no explanation or markdown formatting.
        - For any field not found in the document, use null.
        - The document may be in any language — extract values as they appear.
        """
    }
}
