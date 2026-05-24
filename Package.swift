// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "agent-swarm-management",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentSwarmManagement", targets: ["AgentSwarmManagement"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMajor(from: "2.7.0"))
    ],
    targets: [
        .executableTarget(
            name: "AgentSwarmManagement",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        )
    ]
)
