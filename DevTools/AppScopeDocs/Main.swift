import AppScopeCore
import Darwin
import Foundation
import MCP

// Maintainer-only utility: reads public schemas and synthetic examples. No provider calls.
@main struct AppScopeDocs {
  static func main() {
    do { try run() } catch {
      fputs("AppScope docs: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
  static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty || arguments == ["--check"] else {
      throw ScopeError("usage", "Run from the repository root: swift run appscope-docs [--check]")
    }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let examples = try JSON.decode(
      Data(contentsOf: root.appendingPathComponent("examples/tool-calls.json"))
    ).list
    let names = ToolCatalog.all.map(\.name)
    guard examples.count == names.count, Set(examples.map { $0["name"].text }) == Set(names) else {
      throw ScopeError(
        "example_coverage", "Each tool needs exactly one example in examples/tool-calls.json.")
    }
    for example in examples {
      guard let args = example["arguments"].objectValue else {
        throw ScopeError("invalid_example", "Example arguments must be an object.")
      }
      try ToolCatalog.validate(example["name"].text, args)
      if let app = args["app_id"]?.stringValue { _ = try Validate.appID(app) }
      if let country = args["country"]?.stringValue { _ = try Validate.country(country) }
      if let keyword = args["keyword"]?.stringValue { _ = try Validate.keyword(keyword) }
      for key in ["keywords", "seeds"] {
        for keyword in args[key]?.list ?? [] { _ = try Validate.keyword(keyword.text) }
      }
      for key in ["start", "end", "start_date"] {
        if let date = args[key]?.stringValue { _ = try Validate.date(date) }
      }
      for key in ["run_id", "experiment_id"] {
        if let id = args[key]?.stringValue { _ = try Validate.identifier(id) }
      }
    }

    var markdown = """
      # MCP tool reference

      Generated from `ToolCatalog.all` for AppScope \(appScopeVersion). Run
      `swift run appscope-docs` to regenerate; `swift run appscope-docs --check`
      validates this page, the JSON catalog, examples, fenced JSON and relative file links.

      Examples use the fictional app ID `1234567890`. Replace it with your verified
      numeric app ID. Historical dates demonstrate request format; choose a relevant
      completed period for real use. Examples are schema-checked, not live account tests.

      [Getting started](GETTING-STARTED.md) · [Response guide](RESPONSES.md) ·
      [Errors and troubleshooting](TROUBLESHOOTING.md)

      ## Calling tools

      Your MCP host discovers these tools through `tools/list`. Each example below
      is the `tools/call` parameters object; the host provides the JSON-RPC envelope.
      CLI equivalent: `appscope call TOOL_NAME 'ARGUMENTS_JSON'`.

      Omit optional fields instead of passing null. Undeclared arguments are rejected.
      Country defaults to `us`; use a two-letter ISO country code. App IDs are digit
      strings, not bundle IDs. Keywords are normalized, limited to 100 characters,
      and cannot contain control characters even where an array's item schema is broader.
      Dates must be real YYYY-MM-DD dates. See the response guide for semantic limits.

      MCP annotations describe local side effects. No tool changes live Apple listings
      or campaigns. Read-only tools can still return private account data to your host.

      """
    for tool in ToolCatalog.all {
      markdown += "\n## `\(tool.name)`\n\n\(tool.description ?? "")\n\n"
      let writes = tool.annotations.readOnlyHint == false
      let network = tool.annotations.openWorldHint == true
      markdown +=
        "Local writes: **\(writes ? "yes" : "no")**. Network access: **\(network ? "possible" : "none")**.\n\n"
      let properties = tool.inputSchema["properties"].objectValue ?? [:]
      let required = Set(tool.inputSchema["required"].list.map(\.text))
      if properties.isEmpty {
        markdown += "No arguments.\n\n"
      } else {
        markdown +=
          "| Argument | Type | Required | Default | Constraints and meaning |\n|---|---|---|---|---|\n"
        for key in properties.keys.sorted() {
          let schema = properties[key]!
          var limits: [String] = []
          if key == "country" {
            limits.append("Exactly two ISO letters")
          } else if let max = schema["maxLength"].intValue {
            limits.append("1–\(max) characters")
          }
          if let max = schema["maximum"].intValue {
            limits.append("\(schema["minimum"].intValue ?? 0)–\(max)")
          }
          if let max = schema["maxItems"].intValue { limits.append("0–\(max) items") }
          if let max = schema["items"]["maxLength"].intValue {
            let itemMax = ["keywords", "seeds"].contains(key) ? 100 : max
            limits.append("Each item: 1–\(itemMax) characters")
          }
          if !schema["description"].text.isEmpty { limits.append(schema["description"].text) }
          if let choices = schema["enum"].arrayValue {
            limits.append("Choices: " + choices.map(\.text).joined(separator: ", "))
          }
          let type = schema["type"].text == "array" ? "string array" : schema["type"].text
          let fallback = key == "country" ? "`us`" : "—"
          let defaultText =
            schema["default"] == .null ? fallback : "`\(try schema["default"].jsonText())`"
          let description = limits.joined(separator: "; ").replacingOccurrences(
            of: "|", with: "\\|")
          markdown +=
            "| `\(key)` | \(type) | \(required.contains(key) ? "yes" : "no") | \(defaultText) | \(description) |\n"
        }
        markdown += "\n"
      }
      let example = examples.first { $0["name"].text == tool.name }!
      markdown += "```json\n\(try example.jsonText(pretty: true))\n```\n"
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let catalog = try encoder.encode(ToolCatalog.all)
    let outputs: [String: Data] = [
      "docs/TOOLS.md": Data(markdown.utf8),
      "examples/tool-catalog.json": catalog + Data("\n".utf8),
    ]
    for (path, data) in outputs {
      let url = root.appendingPathComponent(path)
      if arguments == ["--check"] {
        guard (try? Data(contentsOf: url)) == data else {
          throw ScopeError("documentation_drift", "\(path) is stale. Run swift run appscope-docs.")
        }
      } else {
        try data.write(to: url, options: .atomic)
      }
    }
    try checkLinks(root)
    print(
      "Documentation valid: \(names.count) tool schemas and examples; fenced JSON and relative file links checked."
    )
  }

  static func checkLinks(_ root: URL) throws {
    let fm = FileManager.default
    var files = ["README.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md"].map {
      root.appendingPathComponent($0)
    }
    for folder in ["docs", "examples"] {
      let enumerator = fm.enumerator(
        at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)!
      while let url = enumerator.nextObject() as? URL {
        if url.pathExtension == "md" || url.lastPathComponent == "llms.txt" { files.append(url) }
      }
    }
    let pattern = try NSRegularExpression(pattern: #"\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)"#)
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      let jsonBlocks = try NSRegularExpression(pattern: #"(?ms)^```json\s*\n(.*?)^```\s*$"#)
      for block in jsonBlocks.matches(in: source, range: NSRange(source.startIndex..., in: source))
      {
        let body = String(source[Range(block.range(at: 1), in: source)!])
        guard (try? JSON.decode(Data(body.utf8))) != nil else {
          throw ScopeError(
            "invalid_json_example", "\(file.lastPathComponent): invalid fenced JSON example.")
        }
      }
      // Examples in fenced blocks are not document hyperlinks.
      var insideFence = false
      let text = source.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
          insideFence.toggle()
          return false
        }
        return !insideFence
      }.joined(separator: "\n")
      for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        let target = String(text[Range(match.range(at: 1), in: text)!])
        if target.contains(":") || target.hasPrefix("#") { continue }
        let path =
          String(target.split(separator: "#", maxSplits: 1)[0]).removingPercentEncoding ?? target
        let resolved = file.deletingLastPathComponent().appendingPathComponent(path)
          .standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/"), fm.fileExists(atPath: resolved.path) else {
          throw ScopeError(
            "broken_link", "\(file.lastPathComponent): missing relative link \(target)")
        }
      }
    }
  }
}
