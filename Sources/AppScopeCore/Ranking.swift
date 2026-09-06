import Foundation
import MCP

public enum Ranking {
  public static func app(_ item: JSON) throws -> JSON {
    guard let id = item["trackId"].intValue, id > 0, !item["trackName"].text.isEmpty else {
      throw ScopeError(
        "invalid_search_results",
        "A search result is missing its app ID or title. No rank was recorded.")
    }
    return [
      "app_id": .string(String(id)), "title": item["trackName"], "developer": item["sellerName"],
      "genre": item["primaryGenreName"], "rating": item["averageUserRating"],
      "rating_count": item["userRatingCount"], "price": item["price"], "currency": item["currency"],
      "version": item["version"], "updated_at": item["currentVersionReleaseDate"],
      "url": item["trackViewUrl"], "icon_url": item["artworkUrl100"],
    ]
  }
  public static func analyze(
    appID: String, keyword: String, country: String, results: [JSON], limit: Int,
    at: String = timestamp()
  ) throws -> JSON {
    let apps = try results.map(app)
    guard Set(apps.map { $0["app_id"].text }).count == apps.count else {
      throw ScopeError(
        "invalid_search_results",
        "Search results contained duplicate app IDs. No rank was recorded.")
    }
    let position = apps.firstIndex { $0["app_id"].text == appID }.map { $0 + 1 }
    let competitors = apps.enumerated().filter { $0.element["app_id"].text != appID }.prefix(20).map
    { index, app in
      var value = app.objectValue!
      value["position"] = .int(index + 1)
      return JSON.object(value)
    }
    let top = Array(apps.prefix(10).filter { $0["app_id"].text != appID })
    let counts = top.compactMap { $0["rating_count"].intValue }.sorted()
    let median: Double? =
      counts.isEmpty
      ? nil
      : counts.count % 2 == 1
        ? Double(counts[counts.count / 2])
        : (Double(counts[counts.count / 2 - 1]) + Double(counts[counts.count / 2])) / 2
    let matches = top.filter { $0["title"].text.localizedCaseInsensitiveContains(keyword) }.count
    let pressure: String =
      median == nil
      ? "unknown"
      : median! >= 10000 || matches >= 7
        ? "high" : median! >= 1000 || matches >= 4 ? "moderate" : "lower"
    return [
      "app_id": .string(appID), "keyword": .string(keyword), "country": .string(country),
      "rank": position.map(JSON.int) ?? .null,
      "status": .string(position == nil ? "not_found" : "found"),
      "searched_count": .int(apps.count), "requested_limit": .int(limit),
      "source": "itunes_search", "rank_kind": "observed_search_position",
      "observed_at": .string(at),
      "caveat":
        "Search API order is not verified against device App Store results. Not found means absent only from the returned results. A rating count is not a written-review count.",
      "competitors": .array(competitors),
      "competition": [
        "kind": "estimate", "model": "top10-rating-title-v1", "pressure": .string(pressure),
        "sample_size": .int(top.count), "rating_count_sample_size": .int(counts.count),
        "median_rating_count": median.map(JSON.double) ?? .null,
        "title_phrase_matches": .int(matches),
        "method":
          "High: median rating count >=10000 or >=7 title matches. Moderate: >=1000 or >=4 matches. Otherwise lower. Unknown if ratings are absent. This measures competitor strength, not probability of ranking.",
      ],
    ]
  }
}
public struct Storefront: Sendable {
  let http: HTTP
  public init(http: HTTP) { self.http = http }
  public func search(_ keyword: String, country: String, limit: Int = 200) async throws -> [JSON] {
    let data = try await http.json(
      endpoint(
        "https://itunes.apple.com/search",
        query: [
          "term": keyword, "country": country, "media": "software", "entity": "software",
          "limit": String(limit),
        ]), search: true)
    guard let results = data["results"].arrayValue, let count = data["resultCount"].intValue,
      count == results.count
    else {
      throw ScopeError(
        "invalid_search_results", "Search response did not include a valid result list.")
    }
    return results
  }
  public func lookup(_ appID: String, country: String) async throws -> JSON {
    let result = try await http.json(
      endpoint(
        "https://itunes.apple.com/lookup",
        query: ["id": appID, "country": country, "entity": "software"]), search: true)
    guard let items = result["results"].arrayValue else {
      throw ScopeError("invalid_response", "App lookup returned malformed data.")
    }
    guard let item = items.first(where: { String($0["trackId"].intValue ?? 0) == appID }) else {
      throw ScopeError("app_not_found", "The app was not found in this country.")
    }
    var metadata = try Ranking.app(item).objectValue!
    metadata["description"] = item["description"]
    return .object(metadata)
  }
}
