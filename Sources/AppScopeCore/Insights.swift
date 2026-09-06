import Foundation
import MCP

enum EvidenceDates {
  static func dates(start: String, end: String) -> [String] {
    guard start <= end else { return [] }
    var dates: [String] = []
    var current = start
    while current <= end && dates.count < 367 {
      dates.append(current)
      current = dateOffset(current, days: 1)
    }
    return dates
  }
  static func age(_ value: JSON, now: Date) -> Double? {
    guard let date = ISO8601DateFormatter().date(from: value.text) else { return nil }
    let age = now.timeIntervalSince(date)
    return age >= -300 ? max(0, age) : nil
  }
  static func complete(_ summary: JSON, report: String) -> Bool {
    let start = summary["start"].text
    let end = summary["end"].text
    guard (try? Validate.date(start)) != nil, (try? Validate.date(end)) != nil, start <= end else {
      return false
    }
    let expected = Set(dates(start: start, end: end))
    return !expected.isEmpty
      && expected == Set(summary["coverage"][report]["dates_with_reports"].list.map(\.text))
      && expected
        == Set(summary["coverage"][report]["dates_with_matching_country_rows"].list.map(\.text))
      && (summary["coverage"][report]["matching_rows"].intValue ?? 0) > 0
  }
  static func completeMetric(_ summary: JSON, metric: String) -> Bool {
    let coverage = summary["metric_coverage"][metric]
    guard complete(summary, report: coverage["report"].text) else { return false }
    return Set(dates(start: summary["start"].text, end: summary["end"].text))
      == Set(coverage["dates_with_values"].list.map(\.text))
      && summary["metrics"][metric].number != nil
  }
}

public enum ReportHealth {
  public static func evaluate(
    brief: JSON, metadata: JSON, rankings: [JSON], trackedCount: Int,
    popularity: [JSON], performance: JSON, refresh: JSON, adsConfigured: Bool,
    analyticsConfigured: Bool, now: Date = Date()
  ) -> JSON {
    func dated(_ value: JSON, field: String, maximum: Double) -> JSON {
      guard value != .null else { return ["status": "missing"] }
      guard let age = EvidenceDates.age(value[field], now: now) else {
        return [
          "status": "missing", "reason": "invalid_or_future_collection_time",
          "observed_at": value[field],
        ]
      }
      return [
        "status": .string(age <= maximum ? "fresh" : "stale"), "observed_at": value[field],
        "age_seconds": .double(age),
      ]
    }
    let freshRanks = rankings.filter {
      String($0["observed_at"].text.prefix(10)) == day(now)
        && EvidenceDates.age($0["observed_at"], now: now) != nil
    }.count
    let rankStatus =
      trackedCount == 0 || rankings.isEmpty
      ? "missing"
      : freshRanks == trackedCount
        ? "fresh" : freshRanks == 0 && rankings.count == trackedCount ? "stale" : "partial"
    let popularityRows = popularity.map { item in
      dated(item, field: "observed_at", maximum: 7 * 86400).setting([
        "keyword": item["keyword"], "score_available": .bool(item["popularity"].number != nil),
      ])
    }
    let freshScores = popularityRows.filter {
      $0["status"].text == "fresh" && $0["score_available"].boolValue == true
    }.count
    let popStatus =
      freshScores == trackedCount && trackedCount > 0
      ? "fresh"
      : popularity.isEmpty
        ? (adsConfigured ? "missing" : "not_configured")
        : popularityRows.allSatisfy { $0["status"].text == "stale" } ? "stale" : "partial"
    var performanceHealth = dated(performance, field: "generated_at", maximum: 86400)
    if performance == .null && !analyticsConfigured {
      performanceHealth = ["status": "not_configured"]
    } else if performance != .null {
      let end = performance["current"]["end"].text
      if !end.isEmpty && end < dateOffset(day(now), days: -3) {
        performanceHealth = performanceHealth.setting(["status": "stale"])
      }
      let complete = ["current", "previous"].allSatisfy { period in
        Reports.names.allSatisfy { EvidenceDates.complete(performance[period], report: $0) }
          && [
            "first_time_downloads", "redownloads", "impression_events", "product_page_view_events",
            "sales_usd", "proceeds_usd",
          ].allSatisfy { EvidenceDates.completeMetric(performance[period], metric: $0) }
      }
      if performanceHealth["status"].text == "fresh" && !complete {
        performanceHealth = performanceHealth.setting(["status": "partial"])
      }
      performanceHealth = performanceHealth.setting([
        "complete_comparison_coverage": .bool(complete),
        "period_start": performance["current"]["start"],
        "period_end": performance["current"]["end"], "sync": performance["sync"],
      ])
      if performance["sync"]["status"].text == "error" {
        performanceHealth = performanceHealth.setting(["refresh_error": performance["sync"]])
      }
    }
    var sources: [String: JSON] = [
      "brief": [
        "status": .string(brief == .null ? "missing" : "present"),
        "updated_at": brief["updated_at"],
      ],
      "metadata": dated(metadata, field: "observed_at", maximum: 86400),
      "rankings": [
        "status": .string(rankStatus), "tracked": .int(trackedCount),
        "observed": .int(rankings.count), "fresh": .int(freshRanks),
      ],
      "popularity": [
        "status": .string(popStatus), "fresh_scores": .int(freshScores),
        "tracked": .int(trackedCount), "keywords": .array(popularityRows),
      ],
      "performance": performanceHealth,
    ]
    for (kind, source) in [
      ("profile", "metadata"), ("ranking", "rankings"), ("popularity", "popularity"),
      ("performance", "performance"),
    ] {
      let failures = refresh["failed_steps"].list.filter { $0["kind"].text == kind }
      if !failures.isEmpty {
        sources[source] = sources[source]!.setting(["refresh_errors": .array(failures)])
      }
    }
    let complete = sources.values.allSatisfy {
      ["fresh", "present"].contains($0["status"].text)
        && $0["refresh_error"] == .null && $0["refresh_errors"].list.isEmpty
    }
    let available =
      brief != .null || metadata != .null || !rankings.isEmpty || !popularity.isEmpty
      || performance != .null
    return [
      "status": .string(complete ? "complete" : available ? "partial" : "unavailable"),
      "sources": .object(sources), "evaluated_at": .string(timestamp(now)),
      "policy":
        "Ranks: current UTC date. Metadata/performance generation: 24 hours. Popularity: 7 days and a supplied score. Performance also needs matching full periods; conversion rate remains unavailable. Owner briefs have no automatic expiry. Refresh errors are separate from cached evidence freshness.",
    ]
  }
}

enum TrendEvidence {
  static func window(_ snapshots: [JSON], start: String, end: String) -> JSON {
    let selected = snapshots.filter {
      $0["observed_at"].text.prefix(10) >= start && $0["observed_at"].text.prefix(10) <= end
    }
    let found = selected.compactMap { $0["rank"].intValue }
    let dates = Set(selected.map { String($0["observed_at"].text.prefix(10)) })
    let expected = EvidenceDates.dates(start: start, end: end)
    return [
      "start": .string(start), "end": .string(end), "observed_days": .int(dates.count),
      "expected_days": .int(expected.count), "found_days": .int(found.count),
      "not_found_days": .int(selected.filter { $0["status"].text == "not_found" }.count),
      "missing_dates": .strings(expected.filter { !dates.contains($0) }),
      "mean_found_position": found.isEmpty
        ? .null : .double(Double(found.reduce(0, +)) / Double(found.count)),
      "complete_found_coverage": .bool(!expected.isEmpty && found.count == expected.count),
      "definition":
        "Latest depth-200 iTunes observation per UTC date. Mean includes found positions only; missing/not-found dates are not assigned a rank.",
    ]
  }
}

extension AppScope {
  func keywordTrends(
    app: String, country: String, days: Int, minimumChange: Int, offset: Int = 0,
    batchSize: Int = 100, now: Date = Date()
  ) async throws -> JSON {
    let today = day(now)
    let baselineDate = dateOffset(day(now), days: -days)
    let start = dateOffset(today, days: 1 - days)
    let tracked = try await database.list("tracked").filter {
      $0["app_id"].text == app && $0["country"].text == country
    }
    var terms: [JSON] = []
    var changes: [JSON] = []
    let selected = Array(tracked.dropFirst(offset).prefix(batchSize))
    for item in selected {
      let keyword = item["keyword"].text
      let history = try await database.dailySnapshots(
        app: app, country: country, keyword: keyword, start: baselineDate, end: today)
      let current = history.last(where: { $0["observed_at"].text.prefix(10) == today }) ?? .null
      let baseline =
        history.first(where: { $0["observed_at"].text.prefix(10) == baselineDate }) ?? .null
      let delta = baseline["rank"].intValue.flatMap { old in
        current["rank"].intValue.map { old - $0 }
      }
      let crossing =
        baseline["rank"].intValue.flatMap { old in
          current["rank"].intValue.map { (old <= 10) != ($0 <= 10) }
        } ?? false
      let meaningful = delta.map { abs($0) >= minimumChange || crossing } ?? false
      let newCompetitors = current["competitors"].list.prefix(3).filter { candidate in
        baseline["competitors"].arrayValue != nil
          && !baseline["competitors"].list.prefix(3).contains {
            $0["app_id"] == candidate["app_id"]
          }
      }.map { candidate in
        candidate.setting([
          "days_in_top_three": .int(
            history.filter {
              $0["observed_at"].text.prefix(10) >= start
                && $0["competitors"].list.prefix(3).contains { $0["app_id"] == candidate["app_id"] }
            }.count)
        ])
      }
      let window = TrendEvidence.window(history, start: start, end: today)
      let competitorMovements: [JSON] = current["competitors"].list.prefix(3).compactMap {
        candidate in
        guard
          let previous = baseline["competitors"].list.prefix(3).first(where: {
            $0["app_id"] == candidate["app_id"]
          }),
          let before = previous["position"].intValue, let after = candidate["position"].intValue
        else { return nil }
        return [
          "app_id": candidate["app_id"], "title": candidate["title"],
          "previous_position": .int(before),
          "current_position": .int(after), "position_change": .int(before - after),
          "days_in_top_three": .int(
            history.filter {
              $0["observed_at"].text.prefix(10) >= start
                && $0["competitors"].list.prefix(3).contains { $0["app_id"] == candidate["app_id"] }
            }.count),
        ]
      }
      let departed = baseline["competitors"].list.prefix(3).filter { previous in
        current["competitors"].arrayValue != nil
          && !current["competitors"].list.prefix(3).contains { $0["app_id"] == previous["app_id"] }
      }
      let evidence = window.setting([
        "keyword": .string(keyword), "baseline_date": .string(baselineDate),
        "baseline_observation": baseline == .null ? .null : compact(baseline),
        "current_observation": current == .null ? .null : compact(current),
        "latest_observed_at": history.last?["observed_at"] ?? .null,
        "rank_change": delta.map(JSON.int) ?? .null, "meaningful_rank_change": .bool(meaningful),
        "new_top_three_competitors": .array(newCompetitors),
        "departed_top_three_competitors": .array(departed),
        "competitor_movements": .array(competitorMovements),
      ])
      terms.append(evidence)
      var kinds: [String] = []
      if meaningful { kinds.append("rank_movement") }
      if baseline["status"].text == "found" && current["status"].text == "not_found" {
        kinds.append("left_returned_results")
      }
      if baseline["status"].text == "not_found" && current["status"].text == "found" {
        kinds.append("entered_returned_results")
      }
      if newCompetitors.contains(where: { ($0["days_in_top_three"].intValue ?? 0) >= 2 }) {
        kinds.append("recurring_competitor_entry")
      }
      if competitorMovements.contains(where: {
        abs($0["position_change"].intValue ?? 0) >= 2
          && ($0["days_in_top_three"].intValue ?? 0) >= 2
      }) {
        kinds.append("recurring_competitor_movement")
      }
      for kind in kinds {
        changes.append([
          "id": .string("\(app)|\(country)|\(keyword)|\(baselineDate)|\(today)|\(kind)"),
          "kind": .string(kind), "keyword": .string(keyword),
          "rank_change": delta.map(JSON.int) ?? .null,
          "baseline_date": .string(baselineDate), "current_date": .string(today),
          "source": "itunes_search",
          "coverage": window, "new_top_three_competitors": .array(newCompetitors),
        ])
      }
    }
    return [
      "app_id": .string(app), "country": .string(country), "days": .int(days),
      "as_of": .string(today),
      "source": "itunes_search", "requested_limit": 200, "keywords": .array(terms),
      "changes": .array(changes),
      "total_tracked": .int(tracked.count), "offset": .int(offset),
      "next_offset": offset + selected.count < tracked.count
        ? .int(offset + selected.count) : .null,
      "notification_guidance":
        "These are change candidates, not sent notifications. Respect the owner's preferences and retain IDs to avoid duplicate messages. A single change is not proof of a sustained trend or causation.",
    ]
  }
  func briefChange(_ change: JSON) -> JSON {
    let keys = ["id", "kind", "keyword", "rank_change", "baseline_date", "current_date", "source"]
    return .object(Dictionary(uniqueKeysWithValues: keys.map { ($0, change[$0]) }))
  }
  func briefTrends(_ trends: JSON) -> JSON {
    let keys = [
      "keyword", "rank_change", "observed_days", "expected_days", "found_days", "not_found_days",
      "mean_found_position", "meaningful_rank_change",
    ]
    return [
      "days": trends["days"], "as_of": trends["as_of"], "source": trends["source"],
      "requested_limit": trends["requested_limit"],
      "keywords": .array(
        trends["keywords"].list.map { item in
          .object(Dictionary(uniqueKeysWithValues: keys.map { ($0, item[$0]) }))
        }),
      "total_change_candidates": .int(trends["changes"].list.count),
      "details":
        "Use keyword_trends, paging through next_offset, for exact dates and competitor evidence. Daily briefings omit full trend snapshots and show at most 20 change candidates.",
    ]
  }
}
