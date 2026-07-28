// swift-tools-version: 6.0
import PackageDescription

// PlateworksCore is a pure-Swift, dependency-free library that encodes the NWCG
// Incident Response Pocket Guide (IRPG, PMS 461) Fine Fuel Moisture / Probability
// of Ignition tables and the psychrometric relative-humidity relationships.
//
// It has NO UI and NO Apple-framework dependencies, so it builds and its full
// golden-test suite runs on Linux CI as well as on Apple platforms. The
// SwiftUI app (see the `App/` directory and `project.yml`) depends on this core.
let package = Package(
    name: "PlateworksIgnition",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "PlateworksCore", targets: ["PlateworksCore"]),
        .executable(name: "plateworks-vectors", targets: ["PlateworksVectors"])
    ],
    targets: [
        // Swift 6 language mode: full data-race checking. The core is pure value
        // types that were already `Sendable`, so this is enforcement of a
        // property it already had rather than a migration — and it means the app
        // targets, the widget, and the watch app all link a core that is provably
        // safe to touch from any isolation.
        .target(
            name: "PlateworksCore",
            path: "Sources/PlateworksCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Emits conformance/vectors.json — golden vectors the web port
        // (web/engine.js) is checked against in CI. See docs/PARITY.md.
        .executableTarget(
            name: "PlateworksVectors",
            dependencies: ["PlateworksCore"],
            path: "Sources/PlateworksVectors",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PlateworksCoreTests",
            dependencies: ["PlateworksCore"],
            path: "Tests/PlateworksCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
