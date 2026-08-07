// swift-tools-version: 6.0

// OttoPersistence holds spec §3.4 layers 2 and 3 as separate targets so the
// compiler enforces the layering: OttoRepositories (the protocols) depends only
// on OttoDomain and never sees SwiftData; OttoPersistence (the SwiftData
// adapter) implements those protocols and keeps its @Model classes internal, so
// nothing above layer 2 can even name a persistence type.
import PackageDescription

let package = Package(
    name: "OttoPersistence",
    platforms: [
        .iOS("26.0"),
        // macOS is included solely so the tests run on the host via `swift test`,
        // the same way OttoDomain's do - no simulator required.
        .macOS("15.0")
    ],
    products: [
        .library(name: "OttoRepositories", targets: ["OttoRepositories"]),
        .library(name: "OttoPersistence", targets: ["OttoPersistence"])
    ],
    dependencies: [
        .package(path: "../OttoDomain")
    ],
    targets: [
        .target(
            name: "OttoRepositories",
            dependencies: [.product(name: "OttoDomain", package: "OttoDomain")]
        ),
        .target(
            name: "OttoPersistence",
            dependencies: [
                "OttoRepositories",
                .product(name: "OttoDomain", package: "OttoDomain")
            ]
        ),
        .testTarget(name: "OttoPersistenceTests", dependencies: ["OttoPersistence"])
    ],
    swiftLanguageModes: [.v6]
)
