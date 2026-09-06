import Foundation
import MCP

extension AppScope {
  func experimentSummary(_ record: JSON) -> JSON {
    record["definition"].setting([
      "experiment_id": record["experiment_id"], "revision": record["revision"],
      "status": record["status"], "notes": record["notes"], "created_at": record["created_at"],
      "updated_at": record["updated_at"],
    ])
  }
  func experiment(app: String, country: String, id: String) async throws -> JSON {
    let key = try Validate.identifier(id)
    guard let record = try await database.get("experiment", key), record["app_id"].text == app,
      record["country"].text == country
    else {
      throw ScopeError("experiment_not_found", "No matching experiment for this app and country.")
    }
    return record
  }
  func experimentWindow(
    app: String, country: String, keywords: [String], start: String, end: String
  ) async throws -> JSON {
    var ranks: [JSON] = []
    for term in keywords {
      let observations = try await database.dailySnapshots(
        app: app, country: country, keyword: term, start: start, end: end)
      ranks.append(
        TrendEvidence.window(observations, start: start, end: end).setting([
          "keyword": .string(term)
        ]))
    }
    let analytics = try await database.list("analytics")
    return [
      "start": .string(start), "end": .string(end), "keywords": .array(ranks),
      "performance": Reports.summarize(
        analytics, app: app, country: country, start: start, end: end),
    ]
  }
  func recordExperiment(app: String, country: String, args: JSON) async throws -> JSON {
    let start = try Validate.date(args["start_date"].text)
    guard start <= day(), start >= dateOffset(day(), days: -365) else {
      throw ScopeError(
        "invalid_period",
        "Record a change that began within the past year, no later than today UTC.")
    }
    let terms = try Set(args["keywords"].list.map { try Validate.keyword($0.text) }).sorted()
    guard !terms.isEmpty else {
      throw ScopeError("invalid_arguments", "Choose at least one keyword to measure.")
    }
    let id =
      try args["experiment_id"].stringValue.map(Validate.identifier)
      ?? UUID().uuidString.lowercased()
    let days = args["window_days"].intValue ?? 14
    let definition: JSON = [
      "app_id": .string(app), "country": .string(country), "title": args["title"],
      "hypothesis": args["hypothesis"], "change": args["change"], "start_date": .string(start),
      "window_days": .int(days), "keywords": .strings(terms), "original_notes": args["notes"],
    ]
    if let existing = try await database.get("experiment", id) {
      guard existing["definition"] == definition else {
        throw ScopeError(
          "experiment_conflict",
          "This experiment ID already has a different definition. Use its existing record or choose a new ID."
        )
      }
      return existing
    }
    let baseline = try await experimentWindow(
      app: app, country: country, keywords: terms, start: dateOffset(start, days: -days),
      end: dateOffset(start, days: -1))
    let record: JSON = [
      "experiment_id": .string(id), "app_id": .string(app), "country": .string(country),
      "definition": definition, "revision": 1, "status": "running", "notes": args["notes"],
      "created_at": .string(timestamp()), "updated_at": .string(timestamp()),
      "baseline_at_creation": baseline,
    ]
    let saved = try await database.putIfAbsent("experiment", id, record)
    guard saved["definition"] == definition else {
      throw ScopeError(
        "experiment_conflict",
        "Another request created this ID with different details. Read the existing record.")
    }
    return saved
  }
  func updateExperiment(app: String, country: String, args: JSON) async throws -> JSON {
    guard args["status"] != .null || args["notes"] != .null else {
      throw ScopeError("invalid_arguments", "Provide a status or notes to update.")
    }
    let previous = try await experiment(app: app, country: country, id: args["experiment_id"].text)
    let expected = args["expected_revision"].intValue!
    guard previous["revision"].intValue == expected else {
      throw ScopeError("revision_conflict", "Read the current experiment before updating.")
    }
    var changes: [String: JSON] = [
      "revision": .int(expected + 1), "updated_at": .string(timestamp()),
    ]
    if args["status"] != .null { changes["status"] = args["status"] }
    if args["notes"] != .null { changes["notes"] = args["notes"] }
    let updated = previous.setting(changes)
    try await database.replaceRevision(
      "experiment", previous["experiment_id"].text, revision: expected, value: updated)
    return updated
  }
  func experimentReport(app: String, country: String, id: String) async throws -> JSON {
    let record = try await experiment(app: app, country: country, id: id)
    let definition = record["definition"]
    let start = definition["start_date"].text
    let days = definition["window_days"].intValue!
    let terms = definition["keywords"].list.map(\.text)
    let end = dateOffset(start, days: days - 1)
    let baseline = try await experimentWindow(
      app: app, country: country, keywords: terms, start: dateOffset(start, days: -days),
      end: dateOffset(start, days: -1))
    let after = try await experimentWindow(
      app: app, country: country, keywords: terms, start: start, end: end)
    let rankings: [JSON] = zip(baseline["keywords"].list, after["keywords"].list).map {
      before, after in
      let comparable =
        before["complete_found_coverage"].boolValue == true
        && after["complete_found_coverage"].boolValue == true
      let change: Double? =
        comparable
        ? before["mean_found_position"].number.flatMap { b in
          after["mean_found_position"].number.map { b - $0 }
        } : nil
      return [
        "keyword": before["keyword"], "mean_position_change": change.map(JSON.double) ?? .null,
        "comparable": .bool(comparable), "before": before, "after": after,
      ]
    }
    let metricReports = [
      "first_time_downloads": Reports.names[0], "redownloads": Reports.names[0],
      "impression_events": Reports.names[1], "product_page_view_events": Reports.names[1],
      "sales_usd": Reports.names[2], "proceeds_usd": Reports.names[2],
    ]
    var changes: [String: JSON] = [:]
    for metric in metricReports.keys {
      let before = baseline["performance"]
      let next = after["performance"]
      let complete =
        EvidenceDates.completeMetric(before, metric: metric)
        && EvidenceDates.completeMetric(next, metric: metric)
      changes[metric] =
        complete
        ? (before["metrics"][metric].number.flatMap { b in
          next["metrics"][metric].number.map { JSON.double($0 - b) }
        } ?? .null) : .null
    }
    let complete =
      rankings.allSatisfy { $0["comparable"].boolValue == true }
      && changes.values.allSatisfy { $0.number != nil }
    return [
      "experiment": record,
      "status": .string(day() <= end ? "collecting" : complete ? "comparable" : "incomplete"),
      "baseline": baseline, "after": after,
      "baseline_changed_since_recorded": .bool(baseline != record["baseline_at_creation"]),
      "keyword_comparisons": .array(rankings), "performance_changes": .object(changes),
      "generated_at": .string(timestamp()),
      "interpretation":
        "Positive mean_position_change is improved observed API position; performance changes are after minus before. Differences require complete comparable coverage. Full rank comparisons require a found rank each day; not-found is never rank 201. Later analytics imports/corrections may revise the recalculated baseline; the original is preserved. These are associations, not causal attribution or guaranteed success. Record overlapping campaigns/releases in notes.",
    ]
  }
}
