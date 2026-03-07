# Changelog

## Unreleased

## 0.1.0 — 2026-03-06

Initial pre-release of the Iris Swift SDK for structured data extraction from images using LLM providers.

### Added

- `IrisClient` actor with async `parse(_:from:)` API for type-safe image-to-struct extraction
- `@Parseable` macro for compile-time JSON schema generation from Swift structs
- Multi-provider architecture with built-in support for:
  - Anthropic Claude (`IrisProvider.claude(apiKey:)`)
  - OpenAI (`IrisProvider.openAI(apiKey:)`)
  - Google Gemini (`IrisProvider.gemini(apiKey:)`)
  - Ollama (`IrisProvider.ollama(model:)`)
  - Apple Foundation Models (`IrisProvider.appleFoundationModels`)
- Custom provider support via `IrisProvider.custom(_:)` protocol
- Image normalization pipeline with automatic resizing, JPEG compression, and base64 encoding
- `RetryPolicy` with configurable max attempts, base delay, and backoff strategy (fixed, linear, exponential)
- Debug mode with `IrisDebugInfo` capturing raw prompts and responses
- `IrisLogger` with OSLog integration and runtime warnings for schema fallback paths
- Nested `@Parseable` schema expansion with computed `irisSchema` properties
- Mirror-based runtime schema inference as fallback for non-macro types
- Provider output normalization for safe type coercion (quoted numbers, boolean strings, comma decimals)
- DocC documentation for all public types
- Example app (`IrisExample`) demonstrating receipt parsing workflow

### Fixed

- Array property schema detection for `ArrayTypeSyntax` in `@Parseable` macro
- Mirror type inference for nested struct properties
- Dictionary placeholder branch in `PromptBuilder`
- `IrisDebugInfo.init` access level restricted to internal
- Sendable capture safety across all test mock URL protocols
- Eliminated all `nonisolated(unsafe)` usage in favor of actor-based patterns

### Changed

- Renamed `IrisModel` to `IrisProvider` for clarity
- Extracted `_parse` helper to consolidate Stage 2+3 pipeline
- Gated Apple Foundation Models integration tests behind `IRIS_RUN_APPLE_FM_SMOKE=1`
