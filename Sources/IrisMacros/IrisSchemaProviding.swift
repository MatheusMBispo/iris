// Sources/IrisMacros/IrisSchemaProviding.swift

/// Protocol automatically satisfied by types annotated with @Parseable.
/// PromptBuilder uses this at runtime to prefer compile-time generated schema
/// over Mirror reflection.
public protocol IrisSchemaProviding {
    static var irisSchema: String { get }
}
