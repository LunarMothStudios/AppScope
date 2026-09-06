import Foundation
import MCP
import Testing

@testable import AppScopeCore

@Test func realMCPProcessListsCallsAndRejectsInvalidTools() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let binary =
    ProcessInfo.processInfo.environment["APPSCOPE_TEST_BINARY"].map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      ".build/debug/appscope")
  let input = Pipe()
  let output = Pipe()
  let error = Pipe()
  let process = Process()
  process.executableURL = binary
  process.arguments = ["serve"]
  process.environment = ["PATH": "/usr/bin:/bin", "APPSCOPE_DATA_DIR": dir.path]
  process.standardInput = input
  process.standardOutput = output
  process.standardError = error
  try process.run()
  defer {
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
  }
  let client = Client(name: "AppScopeIntegrationTest", version: "1.0")
  let transport = StdioTransport(
    input: .init(rawValue: output.fileHandleForReading.fileDescriptor),
    output: .init(rawValue: input.fileHandleForWriting.fileDescriptor))
  _ = try await client.connect(transport: transport)
  let (tools, _) = try await client.listTools()
  #expect(tools.count == ToolCatalog.all.count)
  #expect(!tools.contains { $0.name == "enable_reports" })
  let (content, failed) = try await client.callTool(name: "setup_status", arguments: [:])
  #expect(failed != true)
  if case .text(let text, _, _) = content[0] {
    let result = try JSON.decode(Data(text.utf8))
    #expect(result["apple_ads"].text == "not_configured")
  } else {
    Issue.record("Expected JSON text")
  }
  let (_, invalid) = try await client.callTool(
    name: "track_keywords", arguments: ["app_id": "12", "keywords": ["budget"]])
  #expect(invalid != true)
  let (_, rejected) = try await client.callTool(
    name: "analyze_keyword", arguments: ["app_id": "12", "keyword": "budget", "limit": -1])
  #expect(rejected == true)
  await client.disconnect()
}
