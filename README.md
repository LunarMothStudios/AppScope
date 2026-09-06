# AppScope

Open-source app intelligence for AI agents. A Swift MCP server for macOS;
no dashboard, background app, or hosted account required.

AppScope combines public App Store search observations, local keyword history,
owner-provided app context, Apple Ads keyword research, and App Store Connect
performance reports. Hex or another MCP host handles scheduling and recommendations.

The project is under active initial development. Setup and validation instructions
will be included with the first working release. No credentials belong in this repository.

## Build

Requires macOS 14+, Swift 6+, and Xcode or Command Line Tools with the matching SDK.

```sh
swift build
swift test
swift run appscope
```

MIT licensed. Not affiliated with Apple.
