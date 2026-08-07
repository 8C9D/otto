// swift-tools-version: 6.0

// OttoDomain is the pure domain layer (spec §3.4, layer 1). It imports nothing
// but Foundation, has no dependencies, and builds and tests with `swift test`
// alone - no Xcode project, no simulator. Keeping it a standalone package makes
// the compiler enforce that boundary rather than discipline.
import PackageDescription

let package = Package(
    name: "OttoDomain",
    products: [
        .library(name: "OttoDomain", targets: ["OttoDomain"])
    ],
    targets: [
        .target(name: "OttoDomain"),
        .testTarget(name: "OttoDomainTests", dependencies: ["OttoDomain"])
    ],
    swiftLanguageModes: [.v6]
)
