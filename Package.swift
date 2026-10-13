// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MellowPhoto", platforms: [.macOS(.v14), .iOS(.v16)], products: [
    .executable(name: "MellowPhoto", targets: ["MellowApp"]),
    .library(name: "MellowCore", targets: ["MellowCore"])
], targets: [
    .target(name: "MellowCore"),
    .executableTarget(name: "MellowApp", dependencies: ["MellowCore"]),
    .testTarget(name: "MellowCoreTests", dependencies: ["MellowCore"])
])
