// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortlessMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PortlessCore"),
        .executableTarget(name: "PortlessMenu", dependencies: ["PortlessCore"]),
        .testTarget(name: "PortlessCoreTests", dependencies: ["PortlessCore"]),
    ]
)
