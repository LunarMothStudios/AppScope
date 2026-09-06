import Foundation
import MCP
import Testing

@testable import AppScopeCore

actor MockHTTP: HTTPTransport {
  var requests: [URLRequest] = []
  var responses: [(Data, Int, [String: String])]
  init(_ responses: [(JSON, Int)]) {
    self.responses = responses.map { (try! $0.0.encoded(), $0.1, [:]) }
  }
  func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
    requests.append(request)
    guard !responses.isEmpty else {
      throw ScopeError("unexpected_request", "No more mock responses.")
    }
    return responses.removeFirst()
  }
}

@Test func failedSearchPreservesHistoryAndCachedSuccessAvoidsNetwork() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["error": "redacted"], 403),
    (
      [
        "resultCount": 2,
        "results": [
          ["trackId": 1, "trackName": "Rival", "userRatingCount": 1000],
          ["trackId": 12, "trackName": "Mine", "userRatingCount": 1],
        ],
      ], 200
    ),
  ])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  let args: [String: JSON] = ["app_id": "12", "keyword": "budget", "country": "us"]
  await #expect(throws: ScopeError.self) { try await scope.call("analyze_keyword", args) }
  let empty = try await scope.call("keyword_history", args)
  #expect(empty["observations"].list.isEmpty)
  let first = try await scope.call("analyze_keyword", args)
  #expect(first["rank"].intValue == 2)
  let second = try await scope.call("analyze_keyword", args)
  #expect(second["cache_hit"].boolValue == true)
  #expect(await transport.requests.count == 2)
  #expect(try await scope.call("keyword_history", args)["observations"].list.count == 1)
}

@Test func trackingIsIdempotentCountryScopedAndReportsMarkMissing() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  _ = try await scope.call(
    "track_keywords", ["app_id": "12", "keywords": ["Budget", "budget", "saving"]])
  _ = try await scope.call(
    "track_keywords", ["app_id": "12", "country": "gb", "keywords": ["budget"]])
  let apps = try await scope.call("list_apps", [:])
  #expect(apps["tracked_keywords"].list.count == 3)
  let report = try await scope.call("daily_report", ["app_id": "12"])
  #expect(report["status"].text == "incomplete")
  #expect(report["missing_keywords"].list.count == 2)
  #expect(report["performance"] == .null)
  #expect(throws: ScopeError.self) {
    try ToolCatalog.validate("analyze_keyword", ["app_id": "12", "keyword": "a", "limit": 100000])
  }
  #expect(throws: ScopeError.self) { try ToolCatalog.validate("setup_status", ["token": "secret"]) }
}

@Test func missingCredentialsDoNotBecomeInventedPerformance() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  let result = try await scope.call("app_performance", ["app_id": "12"])
  #expect(result["sync"]["code"].text == "credentials_missing")
  #expect(result["current"]["status"].text == "no_data")
  #expect(result["current"]["metrics"]["first_time_downloads"] == .null)
}

@Test func dailyMovementUsesPriorDateAndSameSearchDepth() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (
      [
        "resultCount": 2,
        "results": [
          ["trackId": 1, "trackName": "Rival", "userRatingCount": 50],
          ["trackId": 12, "trackName": "Mine", "userRatingCount": 1],
        ],
      ], 200
    )
  ])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  let yesterday = dateOffset(day(), days: -1)
  try await scope.database.saveSnapshot([
    "app_id": "12", "keyword": "budget", "country": "us", "rank": 8, "requested_limit": 200,
    "source": "itunes_search", "observed_at": .string(yesterday + "T10:00:00Z"),
  ])
  try await scope.database.saveSnapshot([
    "app_id": "12", "keyword": "budget", "country": "us", "rank": 5, "requested_limit": 20,
    "source": "itunes_search", "observed_at": .string(yesterday + "T11:00:00Z"),
  ])
  let result = try await scope.call("analyze_keyword", ["app_id": "12", "keyword": "budget"])
  #expect(result["rank_change"].intValue == 6)
  #expect(result["previous_observation"]["rank"].intValue == 8)
}

@Test func refreshReturnsPartialFailuresAndKeepsEachKeywordsHistory() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (["error": "unavailable"], 403),
    (
      ["resultCount": 1, "results": [["trackId": 12, "trackName": "Mine", "userRatingCount": 1]]],
      200
    ),
  ])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget", "saving"]])
  let result = try await scope.call("refresh_rankings", ["app_id": "12"])
  #expect(result["status"].text == "partial")
  #expect(result["errors"].list.count == 1)
  #expect(result["observations"].list.count == 1)
  #expect(result["next_offset"] == .null)
  #expect(try await scope.database.history(app: "12", country: "us", keyword: "budget").isEmpty)
  #expect(try await scope.database.history(app: "12", country: "us", keyword: "saving").count == 1)
}

@Test func simultaneousTrackingUpdatesCannotExceedLimit() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let first = try Database(directory: dir)
  let second = try Database(directory: dir)
  let outcomes = await withTaskGroup(of: Bool.self) { group in
    group.addTask {
      do {
        try await first.updateTracking(
          app: "12", country: "us", terms: (0..<60).map { "one \($0)" }, remove: false)
        return true
      } catch { return false }
    }
    group.addTask {
      do {
        try await second.updateTracking(
          app: "12", country: "us", terms: (0..<60).map { "two \($0)" }, remove: false)
        return true
      } catch { return false }
    }
    var results: [Bool] = []
    for await result in group { results.append(result) }
    return results
  }
  #expect(outcomes.filter { $0 }.count == 1)
  #expect(try await first.list("tracked").count == 60)
}

@Test func ownedAppsReturnsAnObjectForMCPStructuredContent() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([(["data": [["id": "12", "attributes": ["name": "Example"]]]], 200)])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  let result = try await scope.call("owned_apps", [:])
  #expect(result.objectValue != nil)
  #expect(result["apps"].list.first?["id"].text == "12")
}
