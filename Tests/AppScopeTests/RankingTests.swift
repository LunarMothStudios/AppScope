import Foundation
import Testing
@testable import AppScopeCore

@Test func ranksUseSourceOrderAndNeverInventPosition() throws {
    let results: [JSON] = [
        ["trackId": 12, "trackName": "Budget Coach", "userRatingCount": 1000],
        ["trackId": 34, "trackName": "Bram", "userRatingCount": 25]
    ]
    let result = try Ranking.analyze(appID: "34", keyword: "budget", country: "us", results: results, limit: 200)
    #expect(result["rank"].intValue == 2)
    #expect(result["source"].text == "itunes_search")
    #expect(result["rank_kind"].text == "observed_search_position")
    #expect(result["competitors"].list.count == 1)
    let absent = try Ranking.analyze(appID: "99", keyword: "budget", country: "us", results: results, limit: 200)
    #expect(absent["rank"] == .null)
    #expect(absent["searched_count"].intValue == 2)
    #expect(absent["status"].text == "not_found")
    #expect(absent["competition"]["kind"].text == "estimate")
}

@Test func malformedResultsCannotBecomeMissingRank() {
    #expect(throws: ScopeError.self) { try Ranking.analyze(appID: "34", keyword: "budget", country: "us", results: [["oops": true]], limit: 200) }
}

@Test func validationRejectsUnboundedAndMalformedInput() {
    #expect(throws: ScopeError.self) { try Validate.keyword("\n") }
    #expect(throws: ScopeError.self) { try Validate.appID("../12") }
    #expect(throws: ScopeError.self) { try Validate.country("zz") }
    #expect(throws: ScopeError.self) { try Validate.date("2026-02-31") }
}
