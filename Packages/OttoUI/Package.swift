// swift-tools-version: 6.0

// OttoUI holds spec §3.4 layer 5 in two targets: OttoStores (the observable store
// layer and view models) and OttoUI (the SwiftUI views). Both depend on OttoDomain
// and the OttoRepositories protocols ONLY - neither declares OttoPersistence, so
// `import OttoPersistence` anywhere in the UI is a compile error, not a convention.
// Only the app target, the composition root, links the concrete persistence.
import PackageDescription

let package = Package(
    name: "OttoUI",
    platforms: [
        .iOS("26.0"),
        // macOS is included solely so the store and view-model tests run on the
        // host via `swift test`, matching the other packages - no simulator needed.
        .macOS("15.0")
    ],
    products: [
        .library(name: "OttoStores", targets: ["OttoStores"]),
        .library(name: "OttoUI", targets: ["OttoUI"])
    ],
    dependencies: [
        .package(path: "../OttoDomain"),
        .package(path: "../OttoPersistence")
    ],
    targets: [
        .target(
            name: "OttoStores",
            dependencies: [
                .product(name: "OttoDomain", package: "OttoDomain"),
                .product(name: "OttoRepositories", package: "OttoPersistence")
            ]
        ),
        .target(
            name: "OttoUI",
            dependencies: [
                "OttoStores",
                .product(name: "OttoDomain", package: "OttoDomain"),
                .product(name: "OttoRepositories", package: "OttoPersistence")
            ]
        ),
        .testTarget(name: "OttoStoresTests", dependencies: ["OttoStores"]),
        // Renders real views at accessibility type sizes; UIKit-hosted, so it runs
        // on the simulator and compiles to nothing under `swift test` on the host.
        .testTarget(name: "OttoUITests", dependencies: ["OttoUI"])
    ],
    swiftLanguageModes: [.v6]
)
