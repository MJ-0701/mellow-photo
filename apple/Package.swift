// swift-tools-version: 5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency=complete")]

let package = Package(
    name: "MellowKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MellowShared", targets: ["MellowShared"]),
        .library(name: "MellowEditing", targets: ["MellowEditing"]),
        .library(name: "MellowLibrary", targets: ["MellowLibrary"]),
        .library(name: "MellowRendering", targets: ["MellowRendering"]),
        .library(name: "MellowExport", targets: ["MellowExport"]),
    ],
    targets: [
        .target(name: "MellowShared", swiftSettings: strictConcurrency),
        .target(name: "MellowEditing", dependencies: ["MellowShared"], swiftSettings: strictConcurrency),
        .target(name: "MellowLibrary", dependencies: ["MellowShared", "MellowEditing"], swiftSettings: strictConcurrency),
        .target(name: "MellowRendering", dependencies: ["MellowShared"], swiftSettings: strictConcurrency),
        .target(name: "MellowExport", dependencies: ["MellowShared", "MellowRendering"], swiftSettings: strictConcurrency),
        .testTarget(name: "MellowSharedTests", dependencies: ["MellowShared"]),
        .testTarget(name: "MellowEditingTests", dependencies: ["MellowEditing"]),
        .testTarget(name: "MellowLibraryTests", dependencies: ["MellowLibrary"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MellowRenderingTests", dependencies: ["MellowRendering"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MellowExportTests", dependencies: ["MellowExport"]),
    ]
)
