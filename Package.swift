// swift-tools-version: 5.9
import PackageDescription

// BadwaterCore is a pure-Swift, dependency-free library that encodes the NWCG
// Incident Response Pocket Guide (IRPG, PMS 461) Fine Fuel Moisture / Probability
// of Ignition tables and the psychrometric relative-humidity relationships.
//
// It has NO UI and NO Apple-framework dependencies, so it builds and its full
// golden-test suite runs on Linux CI as well as on Apple platforms. The
// SwiftUI app (see the `App/` directory and `project.yml`) depends on this core.
let package = Package(
    name: "BadwaterIgnition",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "BadwaterCore", targets: ["BadwaterCore"])
    ],
    targets: [
        .target(
            name: "BadwaterCore",
            path: "Sources/BadwaterCore"
        ),
        .testTarget(
            name: "BadwaterCoreTests",
            dependencies: ["BadwaterCore"],
            path: "Tests/BadwaterCoreTests"
        )
    ]
)
