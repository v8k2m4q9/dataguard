// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DataGuardCore", platforms: [.macOS(.v14)], products: [.library(name: "DataGuardCore", targets: ["DataGuardCore"])], targets: [
    .target(name: "DataGuardCore", path: "DataGuard/Core"),
    .testTarget(name: "DataGuardCoreTests", dependencies: ["DataGuardCore"], path: "Tests")
])
