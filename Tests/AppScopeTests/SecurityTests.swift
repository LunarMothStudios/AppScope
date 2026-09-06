import CryptoKit
import Foundation
import MCP
import Testing

@testable import AppScopeCore

func testCredentials(_ directory: URL) throws -> Configuration {
  let key = P256.Signing.PrivateKey()
  let file = directory.appendingPathComponent("test-key.p8")
  try key.pemRepresentation.write(to: file, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  return Configuration(
    directory: directory,
    values: [
      "apple_ads": [
        "client_id": "test-client", "team_id": "test-team", "key_id": "test-key",
        "ad_account_id": "123", "private_key_path": .string(file.path),
      ],
      "app_store_connect": [
        "issuer_id": "test-issuer", "key_id": "test-key", "private_key_path": .string(file.path),
      ],
    ])
}

@Test func jwtIsValidES256AndPrivateFilesAreRequired() throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = try testCredentials(dir)
  let token = try config.signJWT("app_store_connect", now: Date(timeIntervalSince1970: 1000))
  let components = token.split(separator: ".").map(String.init)
  func decode(_ text: String) -> Data {
    let base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    return Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4))!
  }
  let claims = try JSON.decode(decode(components[1]))
  #expect(claims["aud"].text == "appstoreconnect-v1")
  #expect(claims["exp"].intValue == 1900)
  let key = try P256.Signing.PrivateKey(
    pemRepresentation: String(
      contentsOf: dir.appendingPathComponent("test-key.p8"), encoding: .utf8))
  #expect(
    key.publicKey.isValidSignature(
      try P256.Signing.ECDSASignature(rawRepresentation: decode(components[2])),
      for: Data((components[0] + "." + components[1]).utf8)))
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent("test-key.p8").path)
  #expect(throws: ScopeError.self) { try config.signJWT("app_store_connect") }
}

@Test func adsOnlyUsesResearchEndpointAndPreservesNullPopularity() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = try testCredentials(dir)
  let transport = MockHTTP([
    (["access_token": "never-log-this", "expires_in": 3600], 200),
    (
      [
        "result": [["text": "budget", "popularity": .null], ["text": "saving", "popularity": 0]],
        "pagination": ["totalCount": 2],
      ], 200
    ),
  ])
  let ads = AppleAds(config: config, http: HTTP(transport: transport, searchInterval: 0))
  let result = try await ads.suggestions(app: "12", country: "us", seeds: ["budget"])
  #expect(result["suggestions"].list[0]["popularity"] == .null)
  #expect(result["suggestions"].list[1]["popularity"].intValue == 0)
  #expect(!(try result.jsonText()).contains("never-log-this"))
  let requests = await transport.requests
  #expect(
    requests[1].url?.absoluteString == "https://api.ads.apple.com/v1/suggestions/keywords/query")
  #expect(requests[1].value(forHTTPHeaderField: "X-Ap-Context") == "adAccountId=123;")
  let body = try JSON.decode(requests[1].httpBody!)
  #expect(body["filters"].list.first?["value"] == ["12"])
  #expect(body["filters"].list.last?["field"].text == "terms")
}

@Test func apiPaginationCannotExfiltrateAuthorization() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let config = try testCredentials(dir)
  let transport = MockHTTP([
    (["data": [], "links": ["next": "https://attacker.example/v1/apps"]], 200)
  ])
  let client = AppStoreConnect(
    config: config, http: HTTP(transport: transport, searchInterval: 0),
    database: try Database(directory: dir))
  await #expect(throws: ScopeError.self) { try await client.apps() }
  #expect(await transport.requests.count == 1)
  #expect(
    !AppStoreConnect.validDownloadURL(URL(string: "https://apple.com.attacker.example/data")!))
  #expect(!AppStoreConnect.validDownloadURL(URL(string: "http://localhost/data")!))
  #expect(
    !AppStoreConnect.validDownloadURL(URL(string: "https://user:pass@reports.apple.com/data")!))
}

@Test func httpErrorsNeverReturnProviderSecrets() async throws {
  let transport = MockHTTP([(["error": "private-key-and-token"], 401)])
  let http = HTTP(transport: transport, searchInterval: 0)
  do {
    _ = try await http.json(URL(string: "https://api.ads.apple.com/v1/test")!)
    Issue.record("Expected error")
  } catch let error as ScopeError {
    #expect(!(try error.json.jsonText()).contains("private-key-and-token"))
  }
}
