// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Iris",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Iris", targets: ["Iris"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "600.0.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.1.0"
        ),
    ],
    targets: [
        // Core library — the public SDK
        .target(
            name: "Iris",
            dependencies: ["IrisMacros"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Macro declarations — public @Parseable annotation
        .target(
            name: "IrisMacros",
            dependencies: ["IrisMacrosPlugin"]
        ),
        // Macro implementation — compiler plugin, separate process at build time
        .macro(
            name: "IrisMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // Executable example app — runnable via `swift run IrisExample`
        .executableTarget(
            name: "IrisExample",
            dependencies: ["Iris"]
        ),
        // Test suite — Swift Testing, no XCTest
        .testTarget(
            name: "IrisTests",
            dependencies: ["Iris"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
