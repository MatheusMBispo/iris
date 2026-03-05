# Iris

> Parse any image into a typed Swift struct using Claude — one line of code.

## Quick Start (30-second example)

```swift
import Iris

@Parseable
struct Receipt {
    let storeName: String?
    let totalAmount: Double?
    let items: [String]?
}

let iris = IrisClient(apiKey: "sk-ant-...")
let receipt = try await iris.parse(fileURL: receiptImageURL, as: Receipt.self)
print(receipt.storeName ?? "Unknown store") // "Whole Foods Market"
```

```swift
// Platform-specific overloads also available:
// iOS:   iris.parse(image: uiImage, as: Receipt.self)
// macOS: iris.parse(image: nsImage, as: Receipt.self)
```

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

## API Key Configuration

```swift
// From environment variable (recommended for development)
let iris = IrisClient() // reads ANTHROPIC_API_KEY automatically

// Or explicitly
let iris = IrisClient(apiKey: "sk-ant-...")
```

> **Production Warning**: Never hardcode your API key in app source code. For published iOS/macOS apps:
> - **Recommended**: Route requests through a server-side proxy that holds the key — the key never touches the client binary
> - **Practical alternative**: Use [SwiftSecretKeys](https://github.com/MatheusMBispo/SwiftSecretKeys) to obfuscate the key in your binary — prevents trivial `strings` extraction, though not a substitute for a proxy in high-security contexts

## Testing Without API Calls

Use `IrisModel.mock` to test your parsing logic without making real Anthropic API calls:

```swift
import Testing
import Iris

@Test func parseReceiptWithoutAPIKey() async throws {
    // IrisClient(model:) init — no apiKey parameter needed at all
    let iris = IrisClient(model: .mock)
    // IrisModel.mock returns valid JSON without any Anthropic API call
    // Use a real image file — ImagePipeline runs before the mock model intercepts
    let url = URL(fileURLWithPath: "Tests/IrisTests/Fixtures/supermarket-receipt.jpg")
    let receipt = try await iris.parse(fileURL: url, as: Receipt.self)
    #expect(receipt.storeName == nil)
    #expect(receipt.totalAmount == nil)
    #expect(receipt.items == nil)
}
```

## Documentation

Full API documentation is available in **Xcode Quick Help** — place the cursor on any `IrisClient`, `IrisModel`, or `IrisError` symbol and press Option-click (or Control-Command-?).

To generate a local DocC archive:

```bash
swift package generate-documentation
```

## Iris vs. Apple Foundation Models + Vision (iOS 26+)

Apple's on-device stack (Foundation Models + `RecognizeDocumentsRequest`) is excellent for specific use cases. Here is an honest comparison:

| | Iris (Claude API) | Apple Foundation Models + Vision |
|---|---|---|
| Min iOS | iOS 16+ | iOS 26+ only |
| Device requirement | Any device | A17 Pro chip or newer |
| Works offline | No | Yes |
| Privacy | Data sent to Anthropic servers | Stays on device |
| Cost | Pay-per-use | Free |
| Custom struct extraction | Full JSON schema | Limited (predefined layouts) |
| Model accuracy | Claude (superior on complex docs) | 3B quantized (good for simple text) |
| Simulator support | Yes | No (physical device only) |

**Use Apple Foundation Models + Vision when:**
- Your app targets iOS 26+ exclusively
- Privacy is non-negotiable (medical, legal, financial data)
- Offline support is required
- You need simple text extraction from standard document layouts

**Use Iris when:**
- You need iOS 16+ support (covers the full range of active devices, not just A17 Pro models)
- You need complex custom struct extraction from real-world documents
- You are building a server-side parsing pipeline
- You need superior accuracy on receipts, invoices, or multi-field documents

## Requirements

- iOS 16+ / macOS 13+
- Xcode 16+
- Anthropic API key ([get one at console.anthropic.com](https://console.anthropic.com))
