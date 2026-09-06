// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppScope",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "appscope", targets: ["AppScopeCLI"]),
        .library(name: "AppScopeCore", targets: ["AppScopeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.11.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .systemLibrary(name: "CZlib", pkgConfig: "zlib"),
        .target(name: "AppScopeCore", dependencies: ["CSQLite", "CZlib", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "AppScopeCLI", dependencies: ["AppScopeCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "AppScopeTests", dependencies: ["AppScopeCore"])
    ]
)
