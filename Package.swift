// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AppScope",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "appscope", targets: ["AppScopeCLI"]),
    .executable(name: "appscope-docs", targets: ["AppScopeDocs"]),
    .library(name: "AppScopeCore", targets: ["AppScopeCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .systemLibrary(name: "CZlib"),
    .target(
      name: "AppScopeCore",
      dependencies: ["CSQLite", "CZlib", .product(name: "MCP", package: "swift-sdk")]),
    .executableTarget(
      name: "AppScopeCLI",
      dependencies: ["AppScopeCore", .product(name: "MCP", package: "swift-sdk")]),
    .executableTarget(
      name: "AppScopeDocs",
      dependencies: ["AppScopeCore", .product(name: "MCP", package: "swift-sdk")],
      path: "DevTools/AppScopeDocs"),
    .testTarget(name: "AppScopeTests", dependencies: ["AppScopeCore"]),
  ]
)
