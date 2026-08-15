// swift-tools-version: 6.0

// OttoUI holds spec §3.4 layers 4 and 5 in three targets: OttoServices (layer 4 -
// the notification scheduler, behind a client protocol so it tests host-side),
// OttoStores (the observable store layer and view models), and OttoUI (the SwiftUI
// views). All depend on OttoDomain and the OttoRepositories protocols ONLY - none
// declares OttoPersistence, so `import OttoPersistence` anywhere here is a compile
// error, not a convention. Only the app target, the composition root, links the
// concrete persistence.
import PackageDescription

let package = Package(
    name: "OttoUI",
    platforms: [
        .iOS("26.0"),
        // macOS is included solely so the store, view-model, and scheduler tests
        // run on the host via `swift test`, matching the other packages.
        .macOS("15.0")
    ],
    products: [
        .library(name: "OttoServices", targets: ["OttoServices"]),
        .library(name: "OttoStores", targets: ["OttoStores"]),
        .library(name: "OttoUI", targets: ["OttoUI"])
    ],
    dependencies: [
        .package(path: "../OttoDomain"),
        .package(path: "../OttoPersistence")
    ],
    targets: [
        .target(
            name: "OttoServices",
            dependencies: [
                .product(name: "OttoDomain", package: "OttoDomain"),
                .product(name: "OttoRepositories", package: "OttoPersistence")
            ]
        ),
        .target(
            name: "OttoStores",
            dependencies: [
                "OttoServices",
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
        .testTarget(name: "OttoServicesTests", dependencies: ["OttoServices"]),
        .testTarget(name: "OttoStoresTests", dependencies: ["OttoStores"]),
        // Renders real views at accessibility type sizes; UIKit-hosted, so it runs
        // on the simulator and compiles to nothing under `swift test` on the host.
        // OttoServices is a direct dependency since R4-2: NotificationCoordinator
        // is inside `#if os(iOS)` and compiles to nothing under host
        // `swift test`, so its tests can only live in this simulator-hosted
        // target, and they need `@testable import OttoServices` to reach it.
        .testTarget(name: "OttoUITests", dependencies: ["OttoUI", "OttoServices"])
    ],
    swiftLanguageModes: [.v6]
)
