// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "RunCore", targets: ["RunCore"])],
    targets: [.target(name: "RunCore", resources: [.process("Resources")]), .testTarget(name: "RunCoreTests", dependencies: ["RunCore"])]
)
