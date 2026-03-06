# Iris

> Parse any image into a typed Swift struct using Claude, OpenAI, Gemini, Ollama, or Apple FM — one line of code.

## Quick Start (30-second example)

```swift
import Iris

@Parseable
struct Receipt {
    let storeName: String?
    let totalAmount: Double?
    let items: [String]?
}

// Claude (default) — swap for any provider, syntax never changes
let iris = IrisClient(apiKey: "sk-ant-...")
let receipt = try await iris.parse(fileURL: receiptImageURL, as: Receipt.self)
print(receipt.storeName ?? "Unknown store") // "Whole Foods Market"
```

> For the most robust typed extraction, prefer `@Parseable` on models that include `Int`, `Double`, or `Bool` fields.

```swift
// Platform-specific overloads also available:
// iOS:   iris.parse(image: uiImage, as: Receipt.self)
// macOS: iris.parse(image: nsImage, as: Receipt.self)
```

> **Providers:** Iris works with Claude, OpenAI GPT-4o, Google Gemini, Ollama (local), and Apple Foundation Models. See [Providers](#providers) to switch with a single line.

## Installation

Add Iris to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/matheusbispo/Iris.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["Iris"]
    ),
]
```

Then import: `import Iris`

## Providers

Iris supports multiple AI providers via `IrisProvider` — a Protocol Witnesses struct. Switch providers with a single line:

```swift
// Claude (default) — best accuracy, iOS 16+
let iris = IrisClient(apiKey: "sk-ant-...")

// OpenAI GPT-4o Vision — strong accuracy, iOS 16+
let iris = IrisClient(provider: .openAI(apiKey: "sk-..."))

// Google Gemini Flash — fast, free tier, iOS 16+
let iris = IrisClient(provider: .gemini(apiKey: "AIza..."))

// Ollama — on-device, free, no API key (requires Ollama running locally)
let iris = IrisClient(provider: .ollama(model: "llama3.2-vision"))

// Apple Foundation Models — on-device, free, no API key (iOS 26+ / macOS 26+ only)
let iris = IrisClient(provider: .appleFoundationModels())

// Testing: see [Testing Without API Calls](#testing-without-api-calls)
let iris = IrisClient(provider: .mock)

// Custom: inject any async closure as a provider
let custom = IrisProvider { imageData, prompt in
    // call any API here
    return #"{"storeName": "Custom Store", "total": 42.0}"#
}
let iris = IrisClient(provider: custom)
```

Switch from Claude to Gemini in **one line**:

```swift
// Before
let iris = IrisClient(apiKey: "sk-ant-...")

// After — same parse() syntax, different provider
let iris = IrisClient(provider: .gemini(apiKey: "AIza..."))
```

## API Key Configuration

Each cloud provider uses its own key. Ollama and Apple Foundation Models require no key.

```swift
// Claude — reads ANTHROPIC_API_KEY from environment (recommended for development)
let iris = IrisClient() // or: IrisClient(apiKey: "sk-ant-...")

// OpenAI — pass key explicitly
let iris = IrisClient(provider: .openAI(apiKey: "sk-..."))

// Gemini — pass key explicitly
let iris = IrisClient(provider: .gemini(apiKey: "AIza..."))

// Ollama / Apple FM — no key needed
let iris = IrisClient(provider: .ollama(model: "llama3.2-vision"))
```

> **Production Warning**: Never hardcode your API key in app source code. For published iOS/macOS apps:
> - **Recommended**: Route requests through a server-side proxy that holds the key — the key never touches the client binary
> - **Practical alternative**: Use [SwiftSecretKeys](https://github.com/MatheusMBispo/SwiftSecretKeys) to obfuscate the key in your binary — prevents trivial `strings` extraction, though not a substitute for a proxy in high-security contexts

## Testing Without API Calls

Use `IrisProvider.mock` to test your parsing logic without making any real API calls:

```swift
import Testing
import Iris

@Test func parseReceiptWithoutAPIKey() async throws {
    // IrisClient(provider:) init — no apiKey parameter needed at all
    let iris = IrisClient(provider: .mock)
    // IrisProvider.mock returns valid JSON without any real API call
    // Use a real image file — ImagePipeline runs before the mock model intercepts
    let url = URL(fileURLWithPath: "Tests/IrisTests/Fixtures/supermarket-receipt.jpg")
    let receipt = try await iris.parse(fileURL: url, as: Receipt.self)
    #expect(receipt.storeName == nil)
    #expect(receipt.totalAmount == nil)
    #expect(receipt.items == nil)
}
```

To run the opt-in Apple Foundation Models smoke test locally:

```bash
IRIS_RUN_APPLE_FM_SMOKE=1 swift test --filter integration_parseSupermarketReceiptWithAppleFoundationModels
```

This only runs when `SystemLanguageModel.default.isAvailable` is `true` on `iOS 26+` / `macOS 26+`.

## Documentation

Full API documentation is available in **Xcode Quick Help** — place the cursor on any `IrisClient`, `IrisProvider`, or `IrisError` symbol and press Option-click (or Control-Command-?).

To generate a local DocC archive:

```bash
swift package generate-documentation
```

## Choosing a Provider

| Provider | Min iOS | Cost | Privacy | API Key | Accuracy |
|---|---|---|---|---|---|
| `.claude(apiKey:)` | iOS 16+ | Pay-per-use | Anthropic servers | Required | Best (complex docs) |
| `.openAI(apiKey:)` | iOS 16+ | Pay-per-use | OpenAI servers | Required | Excellent |
| `.gemini(apiKey:)` | iOS 16+ | Free tier + pay | Google servers | Required | Excellent |
| `.ollama(model:)` | iOS 16+ | Free | On-device | None | Depends on model |
| `.appleFoundationModels()` | iOS 26+ | Free | On-device | None | Good (simple docs) |

**Start with `.claude`** for best accuracy on complex documents.
**Use `.gemini`** if you need a free tier without on-device constraints.
**Use `.ollama`** for fully private, offline inference on any iOS 16+ device.
**Use `.appleFoundationModels()`** if your app targets iOS 26+ exclusively and privacy is non-negotiable.

## Requirements

- iOS 16+ / macOS 13+
- Xcode 16+
- API key required only for cloud providers: [Anthropic](https://console.anthropic.com) (Claude), [OpenAI](https://platform.openai.com), or [Google AI Studio](https://aistudio.google.com) (Gemini)
- No API key needed for Ollama (local) or Apple Foundation Models (iOS 26+ / macOS 26+)
