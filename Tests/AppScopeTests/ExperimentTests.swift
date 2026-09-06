import Foundation
import MCP
import Testing

@testable import AppScopeCore

func experimentArgs() -> [String: JSON] {
  [
    "app_id": "12", "experiment_id": "11111111-1111-4111-8111-111111111111",
    "title": "Clearer budget subtitle",
    "hypothesis": "Relevant wording may improve discovery", "change": "Updated subtitle",
    "start_date": .string(day()),
    "window_days": 7, "keywords": ["budget"],
  ]
}

@Test func experimentsAreIdempotentRevisionCheckedAndKeepOriginalBaseline() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  let args = experimentArgs()
  let created = try await scope.call("record_experiment", args)["experiment"]
  let repeatCreate = try await scope.call("record_experiment", args)["experiment"]
  #expect(created == repeatCreate)
  #expect(created["revision"].intValue == 1)
  var changed = args
  changed["change"] = "Different change"
  await #expect(throws: ScopeError.self) { try await scope.call("record_experiment", changed) }
  let updated = try await scope.call(
    "update_experiment",
    [
      "app_id": "12", "experiment_id": created["experiment_id"],
      "expected_revision": 1, "status": "completed",
      "notes": "Released alongside a marketing campaign",
    ])["experiment"]
  #expect(updated["revision"].intValue == 2)
  #expect(updated["baseline_at_creation"] == created["baseline_at_creation"])
  await #expect(throws: ScopeError.self) {
    try await scope.call(
      "update_experiment",
      [
        "app_id": "12", "experiment_id": created["experiment_id"], "expected_revision": 1,
        "status": "stopped",
      ])
  }
}

@Test func experimentReportsPreserveMissingCoverageAndRejectOtherApps() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  let created = try await scope.call("record_experiment", experimentArgs())["experiment"]
  let result = try await scope.call(
    "experiment_report", ["app_id": "12", "experiment_id": created["experiment_id"]])
  #expect(result["status"].text == "collecting")
  #expect(result["keyword_comparisons"].list[0]["mean_position_change"] == .null)
  #expect(result["performance_changes"]["first_time_downloads"] == .null)
  await #expect(throws: ScopeError.self) {
    try await scope.call(
      "experiment_report", ["app_id": "13", "experiment_id": created["experiment_id"]])
  }
  #expect(try await scope.call("list_experiments", ["app_id": "13"])["experiments"].list.isEmpty)
}

@Test func experimentComparisonRequiresFullCoverageAndExposesCorrectedBaseline() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let scope = try AppScope(config: Configuration(directory: dir))
  let start = dateOffset(day(), days: -9)
  for offset in -7..<7 {
    let date = dateOffset(start, days: offset)
    let before = offset < 0
    try await scope.database.saveSnapshot([
      "app_id": "12", "country": "us", "keyword": "budget", "rank": .int(before ? 20 : 15),
      "status": "found", "source": "itunes_search", "requested_limit": 200,
      "observed_at": .string(date + "T12:00:00Z"),
    ])
    let common: JSON = ["Date": .string(date), "Territory": "US"]
    for (report, rows) in [
      (
        Reports.names[0],
        [
          common.setting([
            "Counts": .string(before ? "10" : "12"), "Download Type": "First-time download",
          ]), common.setting(["Counts": "1", "Download Type": "Redownload"]),
        ]
      ),
      (
        Reports.names[1],
        [
          common.setting(["Counts": "100", "Event": "Impression"]),
          common.setting(["Counts": "30", "Event": "Page view", "Page Type": "Product page"]),
        ]
      ),
      (Reports.names[2], [common.setting(["Sales in USD": "20", "Proceeds in USD": "14"])]),
    ] {
      try await scope.database.saveAnalytics(
        app: "12", report: report, processingDate: date, instanceID: UUID().uuidString, rows: rows)
    }
  }
  var args = experimentArgs()
  args["start_date"] = .string(start)
  let original = try await scope.call("record_experiment", args)["experiment"]
  let query: [String: JSON] = ["app_id": "12", "experiment_id": original["experiment_id"]]
  let first = try await scope.call("experiment_report", query)
  #expect(first["status"].text == "comparable")
  #expect(first["keyword_comparisons"].list[0]["mean_position_change"].number == 5)
  #expect(first["performance_changes"]["first_time_downloads"].number == 14)
  _ = try await scope.call(
    "app_performance",
    [
      "app_id": "12", "start": .string(start), "end": .string(dateOffset(start, days: 6)),
      "sync": false,
    ])
  #expect(
    try await scope.call("daily_report", ["app_id": "12"])["health"]["sources"]["performance"][
      "status"
    ].text == "fresh")
  let date = dateOffset(start, days: -1)
  try await scope.database.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: day(), instanceID: "correction",
    rows: [
      [
        "Date": .string(date), "Territory": "US", "Counts": "20",
        "Download Type": "First-time download",
      ],
      ["Date": .string(date), "Territory": "US", "Counts": "1", "Download Type": "Redownload"],
    ])
  let corrected = try await scope.call("experiment_report", query)
  #expect(corrected["baseline_changed_since_recorded"].boolValue == true)
  #expect(corrected["performance_changes"]["first_time_downloads"].number == 4)
  #expect(corrected["experiment"]["baseline_at_creation"] == original["baseline_at_creation"])
  // Apple may have a report date but no rows for the selected country on that date.
  try await scope.database.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: day(), instanceID: "country-gap",
    rows: [
      [
        "Date": .string(start), "Territory": "GB", "Counts": "12",
        "Download Type": "First-time download",
      ],
      ["Date": .string(start), "Territory": "GB", "Counts": "1", "Download Type": "Redownload"],
    ])
  let missing = try await scope.call("experiment_report", query)
  #expect(missing["status"].text == "incomplete")
  #expect(missing["performance_changes"]["first_time_downloads"] == .null)
  // Even when a country has rows, an individual metric can lack a date.
  try await scope.database.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: day(), instanceID: "metric-gap",
    rows: [
      ["Date": .string(start), "Territory": "US", "Counts": "1", "Download Type": "Redownload"]
    ])
  let metricGap = try await scope.call("experiment_report", query)
  #expect(metricGap["performance_changes"]["first_time_downloads"] == .null)
  #expect(metricGap["performance_changes"]["redownloads"].number == 0)
  _ = try await scope.call(
    "app_performance",
    [
      "app_id": "12", "start": .string(start), "end": .string(dateOffset(start, days: 6)),
      "sync": false,
    ])
  #expect(
    try await scope.call("daily_report", ["app_id": "12"])["health"]["sources"]["performance"][
      "status"
    ].text == "partial")
}
