import Foundation

func normalizeProviderJSONOutput(_ text: String, schemaPrompt: String) -> String {
    let extracted = extractJSON(from: text)
    return sanitizeProviderJSON(extracted, schemaPrompt: schemaPrompt) ?? extracted
}

func sanitizeProviderJSON(_ candidate: String, schemaPrompt: String) -> String? {
    guard let data = candidate.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          var dictionary = object as? [String: Any] else {
        return nil
    }

    let propertyTypes = schemaPropertyTypes(from: schemaPrompt)
    for (key, expectedTypes) in propertyTypes {
        guard let value = dictionary[key] else { continue }
        dictionary[key] = sanitizeProviderValue(value, expectedTypes: expectedTypes)
    }

    guard jsonObject(dictionary, matches: propertyTypes) else {
        return nil
    }
    guard JSONSerialization.isValidJSONObject(dictionary),
          let normalizedData = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
          let normalized = String(data: normalizedData, encoding: .utf8) else {
        return nil
    }
    return normalized
}

func schemaPropertyTypes(from schemaPrompt: String) -> [String: Set<String>] {
    let schemaJSON = extractJSON(from: schemaPrompt)
    guard let data = schemaJSON.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let properties = object["properties"] as? [String: Any] else {
        return [:]
    }

    var result: [String: Set<String>] = [:]
    for (key, rawDescriptor) in properties {
        guard let descriptor = rawDescriptor as? [String: Any],
              let rawType = descriptor["type"] else { continue }
        if let type = rawType as? String {
            result[key] = [type]
        } else if let types = rawType as? [String] {
            result[key] = Set(types)
        }
    }
    return result
}

func sanitizeProviderValue(_ value: Any, expectedTypes: Set<String>) -> Any {
    guard let string = value as? String else {
        return value
    }

    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if expectedTypes.contains("null") {
        let lowered = trimmed.lowercased()
        if lowered == "null" || lowered == "nil" {
            return NSNull()
        }
    }

    if expectedTypes.contains("boolean"), let boolean = parseBooleanLiteral(from: trimmed) {
        return boolean
    }

    if expectedTypes.contains("integer"), let integer = parseNumericLiteral(from: trimmed, integerOnly: true) {
        return integer
    }

    if expectedTypes.contains("number"), let number = parseNumericLiteral(from: trimmed, integerOnly: false) {
        return number
    }

    return value
}

func jsonObject(_ object: [String: Any], matches propertyTypes: [String: Set<String>]) -> Bool {
    for (key, expectedTypes) in propertyTypes {
        guard let value = object[key] else { continue }
        if !jsonValueMatchesSchema(value, expectedTypes: expectedTypes) {
            return false
        }
    }
    return true
}

func jsonValueMatchesSchema(_ value: Any, expectedTypes: Set<String>) -> Bool {
    if value is NSNull {
        return expectedTypes.contains("null")
    }

    if expectedTypes.contains("string"), value is String {
        return true
    }

    if expectedTypes.contains("boolean"), isBoolean(value) {
        return true
    }

    if expectedTypes.contains("integer"), let number = value as? NSNumber, !isBoolean(number) {
        return floor(number.doubleValue) == number.doubleValue
    }

    if expectedTypes.contains("number"), let number = value as? NSNumber, !isBoolean(number) {
        return true
    }

    if expectedTypes.contains("array"), value is [Any] {
        return true
    }

    if expectedTypes.contains("object"), value is [String: Any] {
        return true
    }

    return false
}

func parseBooleanLiteral(from string: String) -> Bool? {
    switch string.lowercased() {
    case "true", "yes":
        return true
    case "false", "no":
        return false
    default:
        return nil
    }
}

func parseNumericLiteral(from string: String, integerOnly: Bool) -> NSNumber? {
    var candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return nil }

    if candidate.hasPrefix("(") && candidate.hasSuffix(")") {
        candidate.removeFirst()
        candidate.removeLast()
        candidate = "-" + candidate
    }

    candidate = candidate.replacingOccurrences(of: " ", with: "")
    candidate = candidate.replacingOccurrences(of: #"(?i)\b(?:usd|eur|gbp|brl|cad|aud|jpy|inr)\b"#, with: "", options: .regularExpression)
    candidate = candidate.replacingOccurrences(of: "R$", with: "")
    candidate = candidate.replacingOccurrences(of: #"[\p{Sc}]"#, with: "", options: .regularExpression)

    guard !candidate.isEmpty,
          candidate.range(of: #"^[+-]?[0-9][0-9.,]*$"#, options: .regularExpression) != nil else {
        return nil
    }

    if candidate.contains(",") && candidate.contains(".") {
        guard let lastComma = candidate.lastIndex(of: ","),
              let lastDot = candidate.lastIndex(of: ".") else {
            return nil
        }
        let decimalIndex = max(lastComma, lastDot)
        let fractionalDigits = candidate.distance(from: candidate.index(after: decimalIndex), to: candidate.endIndex)
        guard (1...2).contains(fractionalDigits) else { return nil }

        let integerPart = candidate[..<decimalIndex].filter { $0 != "," && $0 != "." }
        let fractionalPart = candidate[candidate.index(after: decimalIndex)...]
        candidate = String(integerPart) + "." + String(fractionalPart)
    } else if candidate.contains(",") {
        let commas = candidate.filter { $0 == "," }.count
        guard commas == 1, let commaIndex = candidate.firstIndex(of: ",") else { return nil }
        let fractionalDigits = candidate.distance(from: candidate.index(after: commaIndex), to: candidate.endIndex)
        guard (1...2).contains(fractionalDigits) else { return nil }
        candidate.replaceSubrange(commaIndex...commaIndex, with: ".")
    } else if candidate.filter({ $0 == "." }).count > 1 {
        guard let lastDot = candidate.lastIndex(of: ".") else { return nil }
        let fractionalDigits = candidate.distance(from: candidate.index(after: lastDot), to: candidate.endIndex)
        guard (1...2).contains(fractionalDigits) else { return nil }
        let integerPart = candidate[..<lastDot].filter { $0 != "." }
        let fractionalPart = candidate[candidate.index(after: lastDot)...]
        candidate = String(integerPart) + "." + String(fractionalPart)
    }

    if integerOnly {
        guard !candidate.contains("."), let integer = Int(candidate) else {
            return nil
        }
        return NSNumber(value: integer)
    }

    guard let double = Double(candidate) else {
        return nil
    }
    return NSNumber(value: double)
}

func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

func extractJSON(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if let firstFence = trimmed.range(of: "```") {
        let afterFirstFence = trimmed[firstFence.upperBound...]
        if let secondFenceRel = afterFirstFence.range(of: "```") {
            var fenced = String(afterFirstFence[..<secondFenceRel.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced.hasPrefix("json") {
                fenced.removeFirst(4)
                fenced = fenced.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !fenced.isEmpty {
                return fenced
            }
        }
    }

    if let open = trimmed.firstIndex(of: "{") {
        var depth = 0
        var inString = false
        var escaping = false
        var cursor = open
        while cursor < trimmed.endIndex {
            let ch = trimmed[cursor]
            if inString {
                if escaping {
                    escaping = false
                } else if ch == "\\" {
                    escaping = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(trimmed[open...cursor])
                    }
                }
            }
            cursor = trimmed.index(after: cursor)
        }
    }

    return trimmed
}
