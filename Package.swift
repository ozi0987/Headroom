// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Headroom"),
        .testTarget(name: "HeadroomTests", dependencies: ["Headroom"]),
    ]
)
