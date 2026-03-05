import Testing
import Foundation
@testable import Iris

private let integrationAPIKey: String? = {
    let raw = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = trimmed, !value.isEmpty else {
        return nil
    }
    return value
}()

private let integrationEnabled = integrationAPIKey != nil

extension Tag {
    @Tag static var integration: Self
}

// MARK: - Integration test structs

private struct SupermarketReceipt: Decodable {
    let storeName: String?
    let totalAmount: Double?
    let date: String?
}

private struct RestaurantReceipt: Decodable {
    let restaurantName: String?
    let totalAmount: Double?
    let tip: Double?
}

private struct ServiceInvoice: Decodable {
    let providerName: String?
    let invoiceNumber: String?
    let totalAmount: Double?
    let dueDate: String?
}

private struct LowQualityReceipt: Decodable {
    let storeName: String?
    let totalAmount: Double?
    let items: [String]?
}

// MARK: - Fixture image loading helper

private func fixtureURL(_ name: String) throws -> URL {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: nil,
                                subdirectory: "Fixtures") else {
        throw IrisError.imageUnreadable(reason: "Fixture not found: \(name)")
    }
    return url
}

// MARK: - Integration tests

@Suite("integration", .tags(.integration))
struct IntegrationTests {

    private let apiKey: String? = integrationAPIKey

    @Test(
        "parse supermarket receipt extracts store name and total",
        .enabled(if: integrationEnabled)
    )
    func integration_parseSupermarketReceipt() async throws {
        let key = try #require(apiKey)
        let url = try fixtureURL("supermarket-receipt.jpg")
        let iris = IrisClient(apiKey: key)
        let result = try await iris.parse(fileURL: url, as: SupermarketReceipt.self)
        #expect(result.storeName != nil)
        #expect(result.totalAmount != nil)
    }

    @Test(
        "parse restaurant receipt extracts restaurant name and total",
        .enabled(if: integrationEnabled)
    )
    func integration_parseRestaurantReceipt() async throws {
        let key = try #require(apiKey)
        let url = try fixtureURL("restaurant-receipt.jpg")
        let iris = IrisClient(apiKey: key)
        let result = try await iris.parse(fileURL: url, as: RestaurantReceipt.self)
        #expect(result.restaurantName != nil)
        #expect(result.totalAmount != nil)
    }

    @Test(
        "parse service invoice extracts provider name and amount",
        .enabled(if: integrationEnabled)
    )
    func integration_parseServiceInvoice() async throws {
        let key = try #require(apiKey)
        let url = try fixtureURL("invoice.jpg")
        let iris = IrisClient(apiKey: key)
        let result = try await iris.parse(fileURL: url, as: ServiceInvoice.self)
        #expect(result.providerName != nil || result.totalAmount != nil)
    }

    @Test(
        "parse low-quality receipt returns nil for ambiguous Optional fields — not an error",
        .enabled(if: integrationEnabled)
    )
    func integration_parseLowQualityReceiptOptionalFieldsAreNil() async throws {
        let key = try #require(apiKey)
        let url = try fixtureURL("low-quality-receipt.jpg")
        let iris = IrisClient(apiKey: key)
        // This must NOT throw — Optional fields return nil, not IrisError
        let result = try await iris.parse(fileURL: url, as: LowQualityReceipt.self)
        // Verify ambiguous content yields nil in at least one Optional field.
        #expect(result.storeName == nil || result.totalAmount == nil || result.items == nil)
    }
}
