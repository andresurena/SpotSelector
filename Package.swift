// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotSelector",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QualityCore"),
        .executableTarget(
            name: "SpotSelector",
            dependencies: ["QualityCore"]
        ),
        .testTarget(
            name: "QualityCoreTests",
            dependencies: ["QualityCore"]
        ),
    ]
)
