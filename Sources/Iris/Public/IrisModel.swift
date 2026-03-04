import Foundation

public struct IrisModel: Sendable {
    public var parse: @Sendable (_ imageData: Data, _ prompt: String) async throws -> String

    public init(parse: @escaping @Sendable (_ imageData: Data, _ prompt: String) async throws -> String) {
        self.parse = parse
    }

    public static var claude: IrisModel {
        IrisModel { _, _ in
            throw IrisError.modelFailure(
                message: "IrisModel.claude is not yet wired — full URLSession implementation deferred to Story 2.4"
            )
        }
    }
}
