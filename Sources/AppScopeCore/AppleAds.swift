import MCP
import Foundation

/// Only research endpoints exist here. No arbitrary HTTP operation or campaign writes.
public actor AppleAds {
    let config: Configuration
    let http: HTTP
    var token: String?
    var expires = Date.distantPast
    public init(config: Configuration, http: HTTP) { self.config = config; self.http = http }
    private func accessToken() async throws -> String {
        if let token, expires > Date().addingTimeInterval(60) { return token }
        let credentials = try config.credentials("apple_ads")
        var parts = URLComponents()
        parts.queryItems = ["grant_type": "client_credentials", "scope": "searchadsorg", "client_id": credentials["client_id"].text, "client_secret": try config.signJWT("apple_ads")].map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let data = try await http.request(endpoint("https://appleid.apple.com/auth/oauth2/token"), method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"], body: body)
        guard let result = try? JSON.decode(data), !result["access_token"].text.isEmpty, let lifetime = result["expires_in"].number, lifetime > 60 else { throw ScopeError("invalid_token_response", "Apple did not return a usable access token.") }
        token = result["access_token"].text; expires = Date().addingTimeInterval(lifetime)
        return token!
    }
    private func query(_ path: String, body: JSON) async throws -> JSON {
        let credentials = try config.credentials("apple_ads")
        let account = try Validate.appID(credentials["ad_account_id"].text)
        for attempt in 0..<2 {
            let token = try await accessToken()
            do {
                return try await http.json(endpoint("https://api.ads.apple.com/v1/" + path), method: "POST", headers: ["Authorization": "Bearer \(token)", "X-Ap-Context": "adAccountId=\(account);"], body: body)
            } catch let error as ScopeError where error.code == "provider_http_401" && attempt == 0 { self.token = nil }
        }
        throw ScopeError("unauthorized", "Apple Ads rejected the credentials.")
    }
    public func suggestions(app: String, country: String, seeds: [String], offset: Int = 0) async throws -> JSON {
        var filters: [JSON] = [
            ["field": "promotedObjectId", "operator": "EQUALS", "value": .strings([app])],
            ["field": "promotedObjectType", "operator": "EQUALS", "value": ["APPSTORE_APP"]],
            ["field": "countriesOrRegions", "operator": "IN", "value": .strings([country.uppercased()])]
        ]
        if !seeds.isEmpty { filters.append(["field": "terms", "operator": "IN", "value": .strings(seeds)]) }
        let result = try await query("suggestions/keywords/query", body: ["filters": .array(filters), "pagination": ["offset": .int(offset), "pageSize": 100]])
        guard let rows = result["result"].arrayValue else { throw ScopeError("invalid_response", "Apple keyword suggestions had an unexpected shape.") }
        let normalized = try rows.map { row -> JSON in
            guard !row["text"].text.isEmpty, row["popularity"] == .null || (row["popularity"].intValue.map { (0...100).contains($0) } ?? false) else { throw ScopeError("invalid_response", "Apple returned an invalid keyword suggestion.") }
            return ["keyword": row["text"], "popularity": row["popularity"], "source": "apple_ads_suggestions", "kind": "apple_relative_score"]
        }
        return ["app_id": .string(app), "country": .string(country), "observed_at": .string(timestamp()), "suggestions": .array(normalized), "pagination": result["pagination"], "coverage": "Suggestions are not guaranteed exact-keyword lookups. Null popularity is unknown; it is never replaced with an estimate."]
    }
    public func popularity(country: String, genre: String, start: String, end: String, terms: [String], offset: Int = 0) async throws -> JSON {
        var filters: [JSON] = [["field": "countryOrRegion", "operator": "EQUALS", "value": .string(country.uppercased())], ["field": "genre", "operator": "EQUALS", "value": .string(genre)]]
        if !terms.isEmpty { filters.append(["field": "searchTerm", "operator": "IN", "value": .strings(terms)]) }
        let result = try await query("insights/apps/search-term-popularity/query", body: ["filters": .array(filters), "timeRange": ["start": .string(start), "end": .string(end), "granularity": "WEEKLY_SUN_SAT"], "pagination": ["offset": .int(offset), "pageSize": 100]])
        guard result["result"]["rows"].arrayValue != nil else { throw ScopeError("invalid_response", "Apple popularity data had an unexpected shape.") }
        return ["source": "apple_ads_search_term_popularity", "country": .string(country), "observed_at": .string(timestamp()), "period_start": .string(start), "period_end": .string(end), "rows": result["result"]["rows"], "pagination": result["pagination"], "coverage": "Top eligible terms only. rankInGenre is a keyword demand rank, not an app position. Missing terms have unknown popularity."]
    }
}
