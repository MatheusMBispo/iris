// Sources/IrisMacrosPlugin/ParseableMacro.swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder

public struct ParseableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let properties = extractProperties(from: declaration)

        // Use conformingTo to avoid duplicate conformance if struct already declares Decodable.
        let needsDecodable = protocols.contains { $0.trimmedDescription == "Decodable" }
        let conformanceStr = needsDecodable
            ? "Decodable, IrisSchemaProviding"
            : "IrisSchemaProviding"

        let hasNested = properties.contains { $0.nestedTypeName != nil }

        let ext: ExtensionDeclSyntax
        if hasNested {
            // Emit a computed var body that interpolates NestedType.irisSchema at runtime.
            let body = buildComputedVarBody(from: properties)
            ext = try ExtensionDeclSyntax(
                "extension \(type.trimmed): \(raw: conformanceStr)"
            ) {
                DeclSyntax("static var irisSchema: String {\n\(raw: body)\n}")
            }
        } else {
            // All scalar/array: keep the single-line string literal form for backward compatibility.
            let schema = buildJSONSchema(from: properties)
            let escaped = schema
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            ext = try ExtensionDeclSyntax(
                "extension \(type.trimmed): \(raw: conformanceStr)"
            ) {
                DeclSyntax("static var irisSchema: String { \"\(raw: escaped)\" }")
            }
        }
        return [ext]
    }
}

// MARK: - Property Extraction

private struct PropertyInfo {
    let name: String
    let isOptional: Bool
    let baseTypeName: String      // "string", "integer", "number", "boolean", "array"
    let nestedTypeName: String?   // non-nil when property type is a candidate for NestedType.irisSchema
}

/// Extracts stored var/let properties. Skips static and computed properties.
private func extractProperties(from declaration: some DeclGroupSyntax) -> [PropertyInfo] {
    declaration.memberBlock.members
        .compactMap { $0.decl.as(VariableDeclSyntax.self) }
        .filter { !$0.modifiers.contains { $0.name.text == "static" } }
        .filter { $0.bindings.first?.accessorBlock == nil }  // skip computed
        .compactMap { varDecl -> PropertyInfo? in
            guard
                let binding = varDecl.bindings.first,
                let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                let typeAnnotation = binding.typeAnnotation
            else { return nil }
            let (isOpt, baseType) = optionalInfo(typeAnnotation.type)

            let schemaTypeName: String
            let nestedTypeName: String?

            if baseType.is(ArrayTypeSyntax.self) {
                schemaTypeName = "array"
                nestedTypeName = nil
            } else {
                let rawTypeName = baseType.trimmedDescription
                let mapped = jsonSchemaType(for: rawTypeName)
                schemaTypeName = mapped
                // If the type maps to "string" but is NOT one of the known string types,
                // it is likely a custom/nested @Parseable struct. Mark it for runtime expansion.
                // Optional nested types: skip expansion (use object placeholder per CONTEXT.md).
                if mapped == "string" && !isKnownStringType(rawTypeName) && !isOpt {
                    nestedTypeName = rawTypeName
                } else {
                    nestedTypeName = nil
                }
            }

            return PropertyInfo(
                name: pattern.identifier.text,
                isOptional: isOpt,
                baseTypeName: schemaTypeName,
                nestedTypeName: nestedTypeName
            )
        }
}

/// Detects Optional<T> and T? wrapping, returning (isOptional, baseType).
private func optionalInfo(_ type: TypeSyntax) -> (Bool, TypeSyntax) {
    if let opt = type.as(OptionalTypeSyntax.self) {
        return (true, opt.wrappedType)
    }
    if let ident = type.as(IdentifierTypeSyntax.self),
       ident.name.text == "Optional",
       let firstArg = ident.genericArgumentClause?.arguments.first {
        return (true, firstArg.argument)
    }
    return (false, type)
}

// MARK: - JSON Schema Helpers

/// Maps Swift type names to JSON Schema type strings.
/// Unknown/complex types fall back to "string".
private func jsonSchemaType(for swiftTypeName: String) -> String {
    switch swiftTypeName {
    case "String", "Character", "Substring":  return "string"
    case "Int", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "integer"
    case "Double", "Float", "Float16", "Float80", "CGFloat": return "number"
    case "Bool": return "boolean"
    default: return "string"
    }
}

/// Returns true only for Swift types that are genuinely string-like.
private func isKnownStringType(_ name: String) -> Bool {
    name == "String" || name == "Character" || name == "Substring"
}

/// Builds a compact JSON Schema string (single line, no pretty-printing).
/// Used when there are no nested types (all scalar/array properties).
private func buildJSONSchema(from properties: [PropertyInfo]) -> String {
    let propsJSON = properties.map { prop in
        prop.isOptional
            ? "\"\(prop.name)\":{\"type\":[\"\(prop.baseTypeName)\",\"null\"]}"
            : "\"\(prop.name)\":{\"type\":\"\(prop.baseTypeName)\"}"
    }.joined(separator: ",")

    let required = properties
        .filter { !$0.isOptional }
        .map { "\"\($0.name)\"" }
        .joined(separator: ",")

    var schema = "{\"type\":\"object\",\"properties\":{\(propsJSON)}"
    if !required.isEmpty { schema += ",\"required\":[\(required)]" }
    schema += "}"
    return schema
}

/// Builds the source text for the body of a computed `static var irisSchema: String`
/// when at least one property is a nested @Parseable type.
///
/// Emitted code pattern (for `struct NestedOuter { var name: String; var inner: InnerStruct }`):
///
///     let _inner = InnerStruct.irisSchema
///     let propsJSON = "\"name\":{\"type\":\"string\"}," + "\"inner\":" + _inner
///     return "{\"type\":\"object\",\"properties\":{" + propsJSON + "},\"required\":[\"name\",\"inner\"]}"
///
/// Key invariant: all property names and scalar types are resolved at macro-expansion time and
/// embedded as string literals in the emitted code. Only the nested irisSchema variables remain
/// as runtime references.
private func buildComputedVarBody(from properties: [PropertyInfo]) -> String {
    var lines: [String] = []

    // One binding per nested non-optional property.
    for prop in properties where prop.nestedTypeName != nil {
        lines.append("    let _\(prop.name) = \(prop.nestedTypeName!).irisSchema")
    }

    // Build the propsJSON expression as a series of concatenated string literals and variable refs.
    // We accumulate a "pending raw JSON" string for consecutive scalar properties, flushing
    // it as an escaped Swift string literal when we hit a nested property reference.
    //
    // IMPORTANT: all values embedded in pendingRaw are actual compile-time string values
    // (prop.name, prop.baseTypeName) — NOT Swift interpolation that would leak into emitted code.
    var pendingRaw = ""   // accumulates raw JSON text (no Swift escaping yet)
    var exprParts: [String] = []

    /// Escape a raw JSON segment for embedding in a Swift double-quoted string literal.
    /// Backslashes must be doubled, and double-quotes must be backslash-escaped.
    func swiftStringLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    for (i, prop) in properties.enumerated() {
        let separator = i > 0 ? "," : ""
        // Build the JSON key segment: ,"propName":
        let keySegment = "\(separator)\"\(prop.name)\":"

        if prop.nestedTypeName != nil {
            // Flush pending raw JSON as a string literal.
            pendingRaw += keySegment
            if !pendingRaw.isEmpty {
                exprParts.append(swiftStringLiteral(pendingRaw))
                pendingRaw = ""
            }
            // Append the runtime variable reference.
            exprParts.append("_\(prop.name)")
        } else if prop.isOptional {
            pendingRaw += "\(keySegment){\"type\":[\"\(prop.baseTypeName)\",\"null\"]}"
        } else {
            pendingRaw += "\(keySegment){\"type\":\"\(prop.baseTypeName)\"}"
        }
    }
    // Flush any remaining raw JSON.
    if !pendingRaw.isEmpty {
        exprParts.append(swiftStringLiteral(pendingRaw))
    }

    let propsExpr = exprParts.joined(separator: " + ")
    lines.append("    let propsJSON = \(propsExpr)")

    // Required: non-optional property names embedded as a literal JSON array fragment.
    let requiredLiteral: String = {
        let names = properties
            .filter { !$0.isOptional }
            .map { "\"\($0.name)\"" }
            .joined(separator: ",")
        return names
    }()

    if requiredLiteral.isEmpty {
        let prefix = swiftStringLiteral("{\"type\":\"object\",\"properties\":{")
        let suffix = swiftStringLiteral("}")
        lines.append("    return \(prefix) + propsJSON + \(suffix)")
    } else {
        let prefix = swiftStringLiteral("{\"type\":\"object\",\"properties\":{")
        let suffix = swiftStringLiteral("},\"required\":[\(requiredLiteral)]}")
        lines.append("    return \(prefix) + propsJSON + \(suffix)")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Plugin Entry Point

@main
struct IrisPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ParseableMacro.self]
}
