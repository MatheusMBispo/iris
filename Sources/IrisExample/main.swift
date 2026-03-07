import Foundation
import Iris

@Parseable
struct Receipt { let storeName: String?; let totalAmount: Double?; let date: String?; let items: [String]? }

let args = CommandLine.arguments
guard args.count > 1 else { print("Usage: swift run IrisExample <path-to-receipt-image>"); exit(1) }

let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
guard let apiKey, !apiKey.isEmpty else { print("Error: ANTHROPIC_API_KEY is not set."); exit(1) }

let iris = IrisClient(apiKey: apiKey)
let imageURL = URL(fileURLWithPath: args[1])

do {
    let receipt = try await iris.parse(fileURL: imageURL, as: Receipt.self)
    print("Store: \(receipt.storeName ?? "—")")
    print("Total: \(receipt.totalAmount.map { String($0) } ?? "—")")
    print("Date: \(receipt.date ?? "—")")
    let items = (receipt.items ?? []).joined(separator: ", ")
    print("Items: \(items.isEmpty ? "—" : items)")
} catch let error as IrisError {
    let message: String = switch error { case .invalidAPIKey: "Invalid API key. Check ANTHROPIC_API_KEY."; case .imageUnreadable(let reason): "Could not read image: \(reason)"; case .modelFailure(let msg): "Model failed: \(msg)"; case .decodingFailed: "Model output could not be decoded into Receipt."; case .networkError(let underlying): "Network failure: \(underlying.localizedDescription)" }
    print("Error: \(message)")
    exit(1)
} catch {
    print("Parse failed: \(error.localizedDescription)")
    exit(1)
}
