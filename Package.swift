// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "openstill-mcp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "openstill-mcp", path: "Sources/openstill-mcp"),
        .testTarget(name: "openstill-mcpTests", dependencies: ["openstill-mcp"], path: "Tests/openstill-mcpTests"),
    ]
)
