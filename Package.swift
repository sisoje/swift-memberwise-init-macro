// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MemberwiseInit",
    platforms: [
        .macOS(.v26), .iOS(.v26)
    ],
    products: [
        .library(name: "MemberwiseInit", targets: ["MemberwiseInit"]),
    ],
    dependencies: [
        // swift-syntax 6xx matches Swift 6.x toolchains (601 = 6.1, 602 = 6.2, ... 604 = 6.4).
        // The macro APIs used here are stable across the whole 6xx line.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "700.0.0"),
    ],
    targets: [
        // The macro implementation. Compiled as a compiler plugin; never ships to consumers.
        .macro(
            name: "MemberwiseInitMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The public-facing library that declares the @MemberwiseInit attribute.
        .target(name: "MemberwiseInit", dependencies: ["MemberwiseInitMacros"]),
        // Tests for the macro expansion itself.
        .testTarget(
            name: "MemberwiseInitTests",
            dependencies: [
                "MemberwiseInitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "Examples",
            dependencies: ["MemberwiseInit"],
            path: "Examples"
        ),
    ],
    swiftLanguageModes: [.v6]
)
