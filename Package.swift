// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexToolsCore", targets: ["CodexToolsCore"]),
        .executable(name: "CodexTools", targets: ["CodexTools"])
    ],
    targets: [
        .target(
            name: "CodexToolsCore",
            path: "CodexToolsCore/Sources/CodexToolsCore",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .executableTarget(
            name: "CodexTools",
            dependencies: ["CodexToolsCore"],
            path: "CodexTools/Sources/CodexTools",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "CodexToolsTests",
            dependencies: ["CodexToolsCore", "CodexTools"],
            path: "CodexToolsTests",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "CodexToolsUITests",
            dependencies: ["CodexToolsCore", "CodexTools"],
            path: "CodexToolsUITests",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        )
    ]
)
