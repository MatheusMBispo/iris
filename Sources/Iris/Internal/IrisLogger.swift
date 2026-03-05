import OSLog

enum IrisLogger {
    static let image   = Logger(subsystem: "com.iris.sdk", category: "image")
    static let network = Logger(subsystem: "com.iris.sdk", category: "network")
    static let decode  = Logger(subsystem: "com.iris.sdk", category: "decode")
}
