import Foundation
import MCP
import Testing

@testable import AppScopeCore

func searchFixture() -> JSON {
  ["resultCount": 1, "results": [["trackId": 12, "trackName": "Example", "userRatingCount": 20]]]
}

@Test func rankingCacheCannotCrossUTCDateOrReuseFutureOrDifferentSource() {
  let now = ISO8601DateFormatter().date(from: "2026-09-06T00:05:00Z")!
  let row: JSON = [
    "source": "itunes_search", "requested_limit": 200, "observed_at": "2026-09-05T23:59:00Z",
  ]
  #expect(!Ranking.canReuse(row, limit: 200, now: now))
  let current = row.setting(["observed_at": "2026-09-06T00:01:00Z"])
  #expect(Ranking.canReuse(current, limit: 200, now: now))
  #expect(!Ranking.canReuse(current, limit: 20, now: now))
  #expect(!Ranking.canReuse(current.setting(["source": "another_provider"]), limit: 200, now: now))
  #expect(
    !Ranking.canReuse(
      current.setting(["observed_at": "2026-09-06T00:06:00Z"]), limit: 200, now: now))
}

@Test func refreshAppResumesOnlyFailedStepsAcrossServiceInstances() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (searchFixture(), 200), (["error": "unavailable"], 403), (searchFixture(), 200),
  ])
  let first = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  _ = try await first.call("track_keywords", ["app_id": "12", "keywords": ["budget", "saving"]])
  let result = try await first.call("refresh_app", ["app_id": "12"])
  #expect(result["run"]["status"].text == "partial")
  #expect(result["run"]["failed_steps"].list.count == 1)
  let resumedTransport = MockHTTP([(searchFixture(), 200)])
  let second = try AppScope(
    config: Configuration(directory: dir),
    http: HTTP(transport: resumedTransport, searchInterval: 0))
  let resumed = try await second.call(
    "refresh_app", ["app_id": "12", "run_id": result["run"]["run_id"]])
  #expect(resumed["run"]["status"].text == "completed")
  #expect(await resumedTransport.requests.count == 1)
  #expect(resumed["report"]["rankings"].list.count == 2)
  #expect(resumed["report"]["health"]["sources"]["rankings"]["status"].text == "fresh")
}

@Test func reportHealthDoesNotCallOldPerformanceFreshBecauseRanksAreCurrent() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  try await scope.database.saveSnapshot([
    "app_id": "12", "country": "us", "keyword": "budget", "rank": 2,
    "status": "found", "observed_at": .string(timestamp()), "source": "itunes_search",
    "requested_limit": 200,
  ])
  try await scope.database.put(
    "performance", "12|us",
    [
      "generated_at": .string(dateOffset(day(), days: -10) + "T12:00:00Z"),
      "current": ["end": .string(dateOffset(day(), days: -13))],
    ])
  let report = try await scope.call("daily_report", ["app_id": "12"])
  #expect(report["status"].text == "rankings_current")
  #expect(report["health"]["sources"]["performance"]["status"].text == "stale")
  #expect(report["health"]["status"].text == "partial")
}

@Test func trendsRequireComparableDatesAndUseOneObservationPerDay() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  for (date, rank, depth) in [
    (dateOffset(day(), days: -7), 23, 200), (day(), 18, 200), (day(), 1, 20),
  ] {
    try await scope.database.saveSnapshot([
      "app_id": "12", "country": "us", "keyword": "budget",
      "rank": .int(rank), "status": "found", "source": "itunes_search",
      "requested_limit": .int(depth),
      "observed_at": .string(date + "T00:00:00Z"), "competitors": [],
    ])
  }
  let result = try await scope.call("keyword_trends", ["app_id": "12", "days": 7])
  #expect(result["keywords"].list.first?["rank_change"].intValue == 5)
  #expect(result["keywords"].list.first?["observed_days"].intValue == 1)
  let noBaseline = try await scope.call("keyword_trends", ["app_id": "12", "days": 30])
  #expect(noBaseline["keywords"].list.first?["rank_change"] == .null)
}

actor CancelHTTP: HTTPTransport {
  func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
    throw CancellationError()
  }
}

@Test func cancelledRefreshCheckpointsAndReleasesItsLock() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let first = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: CancelHTTP(), searchInterval: 0))
  await #expect(throws: CancellationError.self) {
    try await first.call("refresh_app", ["app_id": "12"])
  }
  let saved = try await first.call("refresh_status", ["app_id": "12"])
  #expect(saved["run"]["status"].text == "interrupted")
  #expect(saved["run"]["steps"].list.first?["status"].text == "pending")
  let second = try AppScope(
    config: Configuration(directory: dir),
    http: HTTP(transport: MockHTTP([(searchFixture(), 200)]), searchInterval: 0))
  #expect(
    try await second.call("refresh_app", ["app_id": "12"])["run"]["status"].text == "completed")
}

@Test func pausedRefreshFreezesSelectionAndRejectsConflictingOrExpiredResumes() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([(searchFixture(), 200), (searchFixture(), 200)])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  let first = try await scope.call("refresh_app", ["app_id": "12", "max_steps": 1])
  #expect(first["run"]["status"].text == "paused")
  let id = first["run"]["run_id"]
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["saving"]])
  let resumed = try await scope.call("refresh_app", ["app_id": "12", "run_id": id])
  #expect(resumed["run"]["keywords"] == ["budget"])
  #expect(resumed["report"]["missing_keywords"] == ["saving"])
  await #expect(throws: ScopeError.self) {
    try await scope.call("refresh_app", ["app_id": "13", "run_id": id])
  }
  await #expect(throws: ScopeError.self) {
    try await scope.call(
      "refresh_app", ["app_id": "12", "run_id": id, "include_popularity": false])
  }
  let run = try await scope.database.get("refresh_run", id.text)!
  try await scope.database.put(
    "refresh_run", id.text, run.setting(["day": .string(dateOffset(day(), days: -1))]))
  await #expect(throws: ScopeError.self) {
    try await scope.call("refresh_app", ["app_id": "12", "run_id": id])
  }
  #expect(await transport.requests.count == 2)
}

@Test func refreshLockExcludesOtherConnectionsAndRecoversAfterRelease() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let first = try RefreshLock(directory: dir, app: "12", country: "us")
  #expect(throws: ScopeError.self) { try RefreshLock(directory: dir, app: "12", country: "us") }
  let otherCountry = try RefreshLock(directory: dir, app: "12", country: "gb")
  otherCountry.release()
  first.release()
  let next = try RefreshLock(directory: dir, app: "12", country: "us")
  next.release()
}

@Test func trendAveragesDeduplicateDaysAndFlagRecurringCompetitorEntries() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  _ = try await scope.call("track_keywords", ["app_id": "12", "keywords": ["budget"]])
  for (offset, time, rank, rival) in [
    (-7, "12", 20, "old"), (-1, "12", 17, "new"), (0, "10", 1, "old"), (0, "12", 15, "new"),
  ] {
    try await scope.database.saveSnapshot([
      "app_id": "12", "country": "us", "keyword": "budget", "rank": .int(rank),
      "status": "found", "source": "itunes_search", "requested_limit": 200,
      "observed_at": .string(dateOffset(day(), days: offset) + "T\(time):00:00Z"),
      "competitors": [["app_id": .string(rival), "position": 1, "title": "Example competitor"]],
    ])
  }
  let trends = try await scope.call("keyword_trends", ["app_id": "12"])
  let term = trends["keywords"].list[0]
  #expect(term["mean_found_position"].number == 16)
  #expect(term["observed_days"].intValue == 2)
  #expect(term["missing_dates"].list.count == 5)
  #expect(term["new_top_three_competitors"].list[0]["days_in_top_three"].intValue == 2)
  #expect(trends["changes"].list.map { $0["kind"].text }.contains("recurring_competitor_entry"))
}
