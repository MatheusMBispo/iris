import Testing
@testable import Iris

@Suite("IrisClient")
struct IrisClientTests {
    @Test("public API stubs are accessible")
    func publicAPIStubsAreAccessible() {
        let client = IrisClient()
        let model = IrisModel()

        #expect(String(describing: type(of: client)) == "IrisClient")
        #expect(String(describing: type(of: model)) == "IrisModel")
        #expect(String(describing: IrisError.self) == "IrisError")
    }
}
