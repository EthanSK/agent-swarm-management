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
    targets: [
        .executableTarget(
            name: "AgentSwarmManagement"
        )
    ]
)

