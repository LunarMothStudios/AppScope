import AppScopeCore
import Foundation
import MCP
import CryptoKit
import Darwin

@main struct AppScopeCLI {
    static func main() async {
        do { try await run() }
        catch let error as ScopeError { fputs("AppScope [\(error.code)]: \(error.message)\n", stderr); exit(1) }
        catch { fputs("AppScope: operation failed. Check configuration, filesystem access, and network connectivity.\n", stderr); exit(1) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args[0] == "--help" || args[0] == "help" {
            print("""
            AppScope \(appScopeVersion) — app intelligence for MCP agents

            appscope serve                       Start the MCP server over stdio
            appscope setup                       Create private configuration, print MCP connection
            appscope doctor                      Check local setup (no network)
            appscope call TOOL '{"arg":"value"}'  Call a tool directly and print JSON
            appscope enable-reports APP_ID --confirm  One-time Apple report enablement (Admin)
            appscope --version                   Print version

            Data: ~/Library/Application Support/AppScope (override APPSCOPE_DATA_DIR)
            Config: DATA_DIR/config.json (override APPSCOPE_CONFIG)
            Credentials stay in local files. No dashboard, scheduler, or LLM key required.
            """)
            return
        }
        if args[0] == "--version" { print(appScopeVersion); return }
        if args[0] == "setup" { try setup(); return }
        let configuration = try Configuration.load()
        let scope = try AppScope(config: configuration)
        switch args[0] {
        case "doctor": print(try await scope.status().jsonText(pretty: true))
        case "call":
            guard args.count == 3, let object = try JSON.decode(Data(args[2].utf8)).objectValue else { throw ScopeError("usage", "Use: appscope call TOOL '{\"argument\":\"value\"}'") }
            print(try await scope.call(args[1], object).jsonText(pretty: true))
        case "enable-reports":
            guard args.count == 3, args[2] == "--confirm" else { throw ScopeError("usage", "Use: appscope enable-reports APP_ID --confirm. This creates an ongoing analytics report request using an Admin key.") }
            print(try await scope.enableReports(app: args[1]).jsonText(pretty: true))
        case "serve":
            let server = Server(name: "AppScope", version: appScopeVersion, capabilities: .init(tools: .init(listChanged: false)))
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: ToolCatalog.all) }
            await server.withMethodHandler(CallTool.self) { params in
                do {
                    let result = try await scope.call(params.name, params.arguments ?? [:])
                    return try .init(content: [.text(text: try result.jsonText())], structuredContent: result, isError: false)
                } catch let error as ScopeError { return try .init(content: [.text(text: try error.json.jsonText())], structuredContent: error.json, isError: true) }
                catch is CancellationError { return .init(content: [.text(text: "Request cancelled.")], isError: true) }
                catch { return .init(content: [.text(text: "AppScope could not complete the operation. Run appscope doctor; no private error details are returned.")], isError: true) }
            }
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        default: throw ScopeError("usage", "Unknown command. Run appscope --help.")
        }
    }
    static func setup() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AppScope")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = environment["APPSCOPE_CONFIG"].map { URL(fileURLWithPath: $0) } ?? directory.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: path.path) {
            let value: JSON = ["apple_ads": ["client_id": "", "team_id": "", "key_id": "", "ad_account_id": "", "private_key_path": ""], "app_store_connect": ["issuer_id": "", "key_id": "", "private_key_path": ""]]
            guard FileManager.default.createFile(atPath: path.path, contents: try value.encoded(pretty: true), attributes: [.posixPermissions: 0o600]) else { throw ScopeError("setup_error", "Could not create the private configuration file.") }
        }
        try Configuration.checkPrivateFile(path)
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        print("Configuration: \(path.path)\nPublic app searches work immediately. Fill in Apple credentials locally to enable account data. Keep private key files outside this repository and chmod 600 them.\n")
        var connection: [String: JSON] = ["command": .string(binary), "args": ["serve"]]
        if environment["APPSCOPE_DATA_DIR"] != nil || environment["APPSCOPE_CONFIG"] != nil {
            connection["env"] = .object(["APPSCOPE_DATA_DIR": .string(directory.path), "APPSCOPE_CONFIG": .string(path.path)])
        }
        let json: JSON = ["mcpServers": ["appscope": .object(connection)]]
        print(try json.jsonText(pretty: true))
    }
}
