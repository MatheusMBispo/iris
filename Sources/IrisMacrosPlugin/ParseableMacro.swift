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
        let schema = buildJSONSchema(from: properties)

        // Use conformingTo to avoid duplicate conformance if struct already declares Decodable.
        // If the struct already has Decodable, the compiler won't include it in conformingTo.
        let needsDecodable = protocols.contains { $0.trimmedDescription == "Decodable" }
        let conformanceStr = needsDecodable
            ? "Decodable, IrisSchemaProviding"
            : "IrisSchemaProviding"

        // Escape the compact JSON schema for embedding in a regular string literal.
        // Avoids multi-line raw string indentation constraints entirely.
        let escaped = schema
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let ext = try ExtensionDeclSyntax(
            "extension \(type.trimmed): \(raw: conformanceStr)"
        ) {
            DeclSyntax("static var irisSchema: String { \"\(raw: escaped)\" }")
        }
        return [ext]
    }
}

// MARK: - Property Extraction

private struct PropertyInfo {
    let name: String
    let isOptional: Bool
    let baseTypeName: String
    let nestedTypeName: String?  // nil for arrays/primitives; reserved for nested struct expansion (Plan 02)
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
            if baseType.is(ArrayTypeSyntax.self) {
                schemaTypeName = "array"
            } else {
                schemaTypeName = jsonSchemaType(for: baseType.trimmedDescription)
            }
            return PropertyInfo(
                name: pattern.identifier.text,
                isOptional: isOpt,
                baseTypeName: schemaTypeName,
                nestedTypeName: nil
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
/// Unknown/complex types (nested structs, [T], Date, URL) fall back to "string".
/// This is a known limitation — nested struct schemas are not recursively expanded in MVP.
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

/// Builds a compact JSON Schema string (single line, no pretty-printing).
/// Compact format avoids multi-line raw string indentation constraints in macro codegen.
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

// MARK: - Plugin Entry Point

@main
struct IrisPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ParseableMacro.self]
}
