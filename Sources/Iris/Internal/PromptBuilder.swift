import Foundation

enum PromptBuilder {

    // MARK: - Dual Schema Strategy

    // Builds the prompt for the given Decodable type T using two strategies:
    //
    // Strategy 1 — @Parseable schema (preferred, compile-time)
    //   If T conforms to IrisSchemaProviding (synthesized by the @Parseable macro),
    //   uses T.irisSchema: a compile-time JSON Schema with precise types —
    //   "integer" for Int, "number" for Double, "boolean" for Bool.
    //   Access via protocol check (type as? IrisSchemaProviding.Type) — never force-cast.
    //
    // Strategy 2 — Mirror reflection fallback (runtime)
    //   If T is a plain Decodable without @Parseable, falls back to Mirror reflection.
    //   Mirror-derived schemas type ALL fields as "string" (no type fidelity).
    //   Optional fields are correctly marked nullable. Functional but less precise —
    //   use @Parseable for structs with typed numeric or boolean fields.
    static func build<T: Decodable>(for type: T.Type) -> String {
        // Strategy 1: @Parseable types conform to IrisSchemaProviding via macro expansion.
        // Compile-time schema with typed properties — preferred over Mirror.
        if let providing = type as? IrisSchemaProviding.Type {
            return formatPrompt(schema: providing.irisSchema)
        }
        // Strategy 2: Mirror reflection — all fields typed "string", Optional fields nullable.
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

    // Maps a runtime value to its JSON Schema type string using type(of:) inference.
    // Int variants → "integer", Double/Float variants → "number", Bool → "boolean", else → "string".
    private static func jsonSchemaType(fromValue value: Any) -> String {
        switch type(of: value) {
        case is Int.Type, is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type,
             is UInt.Type, is UInt8.Type, is UInt16.Type, is UInt32.Type, is UInt64.Type:
            return "integer"
        case is Double.Type, is Float.Type, is CGFloat.Type:
            return "number"
        case is Bool.Type:
            return "boolean"
        default:
            return "string"
        }
    }

    private static func schemaFromMirror(_ mirror: Mirror, required: Set<String>) -> String {
        var fields: [(name: String, nullable: Bool, jsonType: String)] = []

        for child in mirror.children {
            guard let name = child.label else { continue }
            let childMirror = Mirror(reflecting: child.value)
            let isOptional = childMirror.displayStyle == .optional
            let jsonType: String
            if isOptional {
                if let unwrapped = childMirror.children.first?.value {
                    jsonType = jsonSchemaType(fromValue: unwrapped)
                } else {
                    jsonType = "string"
                }
            } else {
                jsonType = jsonSchemaType(fromValue: child.value)
            }
            fields.append((name: name, nullable: isOptional, jsonType: jsonType))
        }

        var propertyLines: [String] = []
        for field in fields {
            if field.nullable {
                propertyLines.append("    \"\(field.name)\": {\"type\": [\"\(field.jsonType)\", \"null\"]}")
            } else {
                propertyLines.append("    \"\(field.name)\": {\"type\": \"\(field.jsonType)\"}")
            }
        }

        let requiredList = fields
            .map(\.name)
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
            if description.hasPrefix("Dictionary<") {
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
        IrisLogger.prompt.warning("[Iris] PromptBuilder: Mirror fallback produced genericPrompt for \(typeName, privacy: .public). Add @Parseable for typed schema.")
        return """
        Extract all available data from this document image and return it as a JSON object for type \(typeName).

        Rules:
        - Return ONLY the JSON object, with no explanation or markdown formatting.
        - For any field not found in the document, use null.
        - The document may be in any language — extract values as they appear.
        """
    }
}
