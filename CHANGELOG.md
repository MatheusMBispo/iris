# Changelog

## Unreleased

- Harden provider output normalization across Claude, OpenAI, Gemini, Ollama, and Apple Foundation Models.
- Normalize safe typed-value mismatches such as quoted currency numbers, comma decimals, boolean strings, and quoted nulls when the schema makes the conversion unambiguous.
- Preserve fail-fast behavior for ambiguous numeric formats instead of guessing.
- Expand Apple Foundation Models real smoke coverage to both receipt and invoice fixtures behind `IRIS_RUN_APPLE_FM_SMOKE=1`.
- Clarify that `@Parseable` is the recommended path for robust typed extraction with `Int`, `Double`, and `Bool` fields.
