// Sources/IrisMacros/Parseable.swift
// No imports — macro declaration is self-contained; plugin referenced by string below.

/// Generates Decodable conformance and a static irisSchema property
/// containing a JSON Schema derived from the struct's stored properties.
///
/// Usage:
/// ```swift
/// @Parseable
/// struct Receipt {
///     var store: String
///     var total: Double
///     var date: String?
/// }
/// ```
@attached(extension, conformances: Decodable, IrisSchemaProviding, names: named(irisSchema))
public macro Parseable() = #externalMacro(module: "IrisMacrosPlugin", type: "ParseableMacro")
