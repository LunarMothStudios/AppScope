import Foundation
import MCP
import Testing

@testable import AppScopeCore

func scratch() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "appscope-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
let downloadHeader = "Date\tApp Apple Identifier\tTerritory\tSource Type\tDownload Type\tCounts\n"
func download(_ date: String, _ count: Int) -> JSON {
  [
    "Date": .string(date), "App Apple Identifier": "12", "Territory": "US",
    "Source Type": "App Store search", "Download Type": "First-time Download",
    "Counts": .string(String(count)),
  ]
}

@Test func parsesQuotedTSVAndRejectsCorruption() throws {
  let parsed = try Reports.parse(
    Data(
      (downloadHeader + "2026-09-01\t12\tUS\t\"App Store\tsearch\"\tFirst-time Download\t12\n").utf8
    ), report: Reports.names[0], appID: "12")
  #expect(parsed.count == 1)
  #expect(parsed[0]["Source Type"].text == "App Store\tsearch")
  #expect(throws: ScopeError.self) {
    try Reports.parse(
      Data((downloadHeader + "2026-09-01\t99\tUS\tSearch\tFirst-time Download\t12\n").utf8),
      report: Reports.names[0], appID: "12")
  }
  #expect(throws: ScopeError.self) {
    try Reports.parse(
      Data((downloadHeader + "2026-09-01\t12\tUS\tSearch\tFirst-time Download\tNaN\n").utf8),
      report: Reports.names[0], appID: "12")
  }
  #expect(throws: ScopeError.self) {
    try Reports.parse(Data([0x1f, 0x8b, 0]), report: Reports.names[0], appID: "12")
  }
}

@Test func correctedReportReplacesDateAndOlderReportsCannotOverwrite() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let db = try Database(directory: dir)
  try await db.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: "2026-09-03", instanceID: "old",
    rows: [download("2026-09-01", 10)])
  try await db.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: "2026-09-04", instanceID: "new",
    rows: [download("2026-09-01", 12)])
  try await db.saveAnalytics(
    app: "12", report: Reports.names[0], processingDate: "2026-09-02", instanceID: "older",
    rows: [download("2026-09-01", 99)])
  let records = try await db.list("analytics")
  #expect(records.count == 1)
  let result = Reports.summarize(
    records, app: "12", country: "us", start: "2026-09-01", end: "2026-09-01")
  #expect(result["metrics"]["first_time_downloads"].number == 12)
  #expect(result["metrics"]["apple_conversion_rate"] == .null)
  #expect(result["metrics"]["sales_usd"] == .null)
  let absent = Reports.summarize(
    records, app: "12", country: "gb", start: "2026-09-01", end: "2026-09-01")
  #expect(absent["metrics"]["first_time_downloads"] == .null)
}

@Test func refundProceedsStayNegativeAndUniqueUsersAreNotSummed() throws {
  let header =
    "Date\tApp Apple Identifier\tTerritory\tSource Type\tSales in USD\tProceeds in USD\tPurchases\tPaying Users\n"
  let rows = try Reports.parse(
    Data((header + "2026-09-01\t12\tUS\tSearch\t-3.00\t-2.10\t-1\t5\n").utf8),
    report: Reports.names[2], appID: "12")
  let result = Reports.summarize(
    [
      [
        "app_id": "12", "report": .string(Reports.names[2]), "date": "2026-09-01",
        "rows": .array(rows),
      ]
    ], app: "12", country: "us", start: "2026-09-01", end: "2026-09-01")
  #expect(result["metrics"]["sales_usd"].number == -3)
  #expect(result["metrics"]["paying_users"] == .null)
}

@Test func absentMetricRowsStayUnknownButExplicitZeroIsPreserved() {
  let zero: JSON = [
    "app_id": "12", "report": "App Store Downloads", "date": "2026-09-01",
    "rows": .array([download("2026-09-01", 0)]),
  ]
  let result = Reports.summarize(
    [zero], app: "12", country: "us", start: "2026-09-01", end: "2026-09-01")
  #expect(result["metrics"]["first_time_downloads"].number == 0)
  #expect(result["metrics"]["redownloads"] == .null)
}
