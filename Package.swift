// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CopilotMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CopilotMeter"),
        .testTarget(name: "CopilotMeterTests", dependencies: ["CopilotMeter"])
    ]
)
