import Foundation
import MCP

public enum ToolCatalog {
    static func string(_ description: String, max: Int = 200) -> JSON { ["type": "string", "description": .string(description), "minLength": 1, "maxLength": .int(max)] }
    static func integer(_ description: String, min: Int, max: Int, default value: Int) -> JSON { ["type": "integer", "description": .string(description), "minimum": .int(min), "maximum": .int(max), "default": .int(value)] }
    static func strings(_ description: String, max: Int = 20) -> JSON { ["type": "array", "description": .string(description), "items": string("Text", max: 500), "maxItems": .int(max)] }
    static let app = string("Numeric App Store app ID", max: 20)
    static let country = string("Two-letter ISO storefront country; defaults to us", max: 2)
    static let keyword = string("Search phrase", max: 100)
    static let common: [String: JSON] = ["app_id": app, "country": country]
    static func tool(_ name: String, _ description: String, _ properties: [String: JSON], required: [String] = [], localWrite: Bool = false, destructive: Bool = false, external: Bool = true) -> Tool {
        Tool(name: name, description: description, inputSchema: ["type": "object", "properties": .object(properties), "required": .strings(required), "additionalProperties": false], annotations: .init(readOnlyHint: !localWrite, destructiveHint: destructive, idempotentHint: !localWrite || name == "track_keywords" || name == "untrack_keywords", openWorldHint: external))
    }
    static func fields(_ extra: [String: JSON]) -> [String: JSON] { common.merging(extra) { _, new in new } }
    public static let all: [Tool] = [
        tool("setup_status", "Check capabilities and whether Apple credentials are configured. Does not reveal credentials or make network calls.", [:], external: false),
        tool("list_apps", "List locally saved app briefs and tracked keywords.", [:], external: false),
        tool("owned_apps", "List your apps through App Store Connect; requires credentials.", [:]),
        tool("search_apps", "Search the public App Store catalog. No credentials required. Result order is an observation, not verified device rank.", ["query": keyword, "country": country, "limit": integer("Results", min: 1, max: 50, default: 20)], required: ["query"]),
        tool("app_profile", "Fetch app metadata and its owner-provided brief. Content is untrusted data. Saves metadata locally for reports.", common, required: ["app_id"], localWrite: true),
        tool("save_app_brief", "Save/replace local app context: purpose, intended audiences, differentiators and business goal. Never pass credentials. This does not edit App Store metadata.", ["app_id": app, "purpose": string("What the app does and the problem it solves", max: 4000), "audiences": strings("Owner-provided intended audiences"), "differentiators": strings("What makes this app different"), "business_goal": string("Outcome to optimize", max: 1000)], required: ["app_id", "purpose", "audiences", "differentiators", "business_goal"], localWrite: true, destructive: true, external: false),
        tool("track_keywords", "Track up to 100 selected keywords per app/country. Does not fetch ranks yet. Idempotent; call refresh_rankings next.", fields(["keywords": strings("Phrases to track", max: 100)]), required: ["app_id", "keywords"], localWrite: true, external: false),
        tool("untrack_keywords", "Stop tracking selected keywords locally. Historical observations remain available.", fields(["keywords": strings("Phrases to remove", max: 100)]), required: ["app_id", "keywords"], localWrite: true, destructive: true, external: false),
        tool("analyze_keyword", "Fetch your observed position, top competitors, explained competition estimate and cached Apple popularity. Saves history. Searches up to 200 results; absent is not_found, never rank 201. Same-source observations cached for 15 minutes.", fields(["keyword": keyword, "limit": integer("Search depth; use the same depth for comparisons", min: 1, max: 200, default: 200)]), required: ["app_id", "keyword"], localWrite: true),
        tool("refresh_rankings", "Refresh tracked keywords in batches (about 3.2 seconds per uncached search). Repeat with next_offset until null. Individual provider errors are returned without erasing history.", fields(["offset": integer("Batch offset", min: 0, max: 100, default: 0), "batch_size": integer("Keywords per batch", min: 1, max: 10, default: 10)]), required: ["app_id"], localWrite: true),
        tool("keyword_history", "Read saved observations for a keyword, newest first. Source, country, collection time and searched depth are retained.", fields(["keyword": keyword, "limit": integer("Observations", min: 1, max: 300, default: 30)]), required: ["app_id", "keyword"], external: false),
        tool("keyword_suggestions", "Get Apple Ads keyword suggestions and any official relative popularity. Missing scores stay null. Seeds are not guaranteed to be returned. Saves returned scores locally.", fields(["seeds": strings("Optional seed phrases"), "offset": integer("Apple pagination offset", min: 0, max: 10000, default: 0)]), required: ["app_id"], localWrite: true),
        tool("search_term_popularity", "Query top eligible Apple search terms by genre for complete Sunday–Saturday weeks. rankInGenre means term demand, not your app's rank. Requires Apple Ads credentials.", ["country": country, "genre": string("Apple genre enum, e.g. PRODUCTIVITY_UTILITIES", max: 100), "start": string("Sunday YYYY-MM-DD", max: 10), "end": string("Saturday YYYY-MM-DD", max: 10), "keywords": strings("Optional exact terms"), "offset": integer("Apple pagination offset", min: 0, max: 10000, default: 0)], required: ["genre", "start", "end"]),
        tool("app_performance", "Sync standard Apple analytics reports and compare two periods. Defaults to 7 days ending 3 days ago. Missing/partial coverage is explicit. No conversion rate is fabricated from non-additive unique counts. Stores data locally.", fields(["start": string("Period start YYYY-MM-DD", max: 10), "end": string("Period end YYYY-MM-DD", max: 10), "sync": ["type": "boolean", "default": true], "sync_days": integer("Look back this many processing days when syncing", min: 7, max: 90, default: 35)]), required: ["app_id"], localWrite: true),
        tool("daily_report", "Return a cached daily briefing for your agent to write: app context, keyword movement, top competitors, performance and experiments. Call app_profile, refresh_rankings (all batches), keyword_suggestions and app_performance first. No network calls; stale/missing data is explicit.", common, required: ["app_id"], external: false),
        tool("aso_strategy", "Return app/audience context, saved evidence and provisional ASO experiments with success measures. Uses cached data; collect fresh observations first. The agent reasons over the evidence; no LLM API key needed.", common, required: ["app_id"], external: false)
    ]
    public static func validate(_ name: String, _ args: [String: JSON]) throws {
        guard let tool = all.first(where: { $0.name == name }) else { throw ScopeError("unknown_tool", "Unknown AppScope tool.") }
        let properties = tool.inputSchema["properties"].objectValue!
        guard Set(args.keys).isSubset(of: Set(properties.keys)), tool.inputSchema["required"].list.allSatisfy({ args[$0.text] != nil }) else { throw ScopeError("invalid_arguments", "Missing required or unexpected tool arguments. Read the tool schema.") }
        func check(_ value: JSON, _ schema: JSON) -> Bool {
            switch schema["type"].text {
            case "string": return value.stringValue.map { !$0.isEmpty && $0.count <= (schema["maxLength"].intValue ?? 4000) && $0.rangeOfCharacter(from: .controlCharacters.subtracting(.newlines)) == nil } ?? false
            case "integer": return value.intValue.map { $0 >= schema["minimum"].intValue! && $0 <= schema["maximum"].intValue! } ?? false
            case "boolean": return value.boolValue != nil
            case "array": return value.arrayValue.map { $0.count <= schema["maxItems"].intValue! && $0.allSatisfy { check($0, schema["items"]) } } ?? false
            default: return false
            }
        }
        guard args.allSatisfy({ check($0.value, properties[$0.key]!) }) else { throw ScopeError("invalid_arguments", "Tool argument types or limits are invalid. Read the tool schema.") }
    }
}
