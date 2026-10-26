// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlainMount",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PlainMount", targets: ["PlainMount"])],
    targets: [
        .target(name: "MountCore"),
        .executableTarget(name: "PlainMount", dependencies: ["MountCore"])
    ]
)
