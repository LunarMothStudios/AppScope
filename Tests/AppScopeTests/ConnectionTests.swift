import CryptoKit
import Foundation
import MCP
import Testing

@testable import AppScopeCore

@Test func connectionCheckSkipsMissingProvidersAndDoesNotPersistAccountData() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([(searchFixture(), 200)])
  let scope = try AppScope(
    config: Configuration(directory: dir), http: HTTP(transport: transport, searchInterval: 0))
  let result = try await scope.call("check_connections", ["app_id": "12"])
  #expect(result["checks"]["public_search"]["status"].text == "ok")
  #expect(result["checks"]["apple_ads"]["status"].text == "not_configured")
  #expect(try await scope.database.list("app").isEmpty)
  #expect(await transport.requests.count == 1)
}

@Test func liveChecksKeepIndependentFailuresAndNeverReturnTokens() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let transport = MockHTTP([
    (searchFixture(), 200),
    (["access_token": "fixture-token-never-return", "expires_in": 3600], 200),
    (["error": "fixture-private-provider-detail"], 403),
    (["data": ["id": "12", "attributes": ["name": "Private app"]]], 200),
    (["data": []], 200),
  ])
  let scope = try AppScope(
    config: testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0))
  let result = try await scope.call("check_connections", ["app_id": "12"])
  #expect(result["checks"]["apple_ads"]["code"].text == "provider_http_403")
  #expect(result["checks"]["app_store_connect"]["status"].text == "ok")
  #expect(result["checks"]["app_store_connect"]["ongoing_reports_enabled"].boolValue == false)
  let text = try result.jsonText()
  #expect(!text.contains("fixture-token-never-return"))
  #expect(!text.contains("fixture-private-provider-detail"))
  #expect(!text.contains("Private app"))
  #expect(try await scope.database.list("analytics").isEmpty)
}

@Test func guidedSetupPreservesOtherProviderAndRejectsInvalidKeysWithoutChangingConfig() throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let env = ["APPSCOPE_DATA_DIR": dir.path]
  let generated = try CredentialSetup.generateAdsKey(environment: env)
  #expect(try !generated.jsonText().contains("BEGIN PRIVATE KEY"))
  let keyURL = URL(fileURLWithPath: generated["private_key_path"].text)
  let originalKey = try Data(contentsOf: keyURL)
  #expect(throws: ScopeError.self) { try CredentialSetup.generateAdsKey(environment: env) }
  #expect(try Data(contentsOf: keyURL) == originalKey)
  let key = try P256.Signing.PrivateKey(
    pemRepresentation: String(decoding: originalKey, as: UTF8.self))
  #expect(generated["public_key"].text == key.publicKey.pemRepresentation)
  let ads: [String: JSON] = [
    "client_id": "fixture-client", "team_id": "fixture-team", "key_id": "fixture-key",
    "ad_account_id": "123", "private_key_path": generated["private_key_path"],
  ]
  try CredentialSetup.save(provider: "apple_ads", fields: ads, environment: env)
  try CredentialSetup.save(
    provider: "app_store_connect",
    fields: [
      "issuer_id": "fixture-issuer", "key_id": "fixture-key",
      "private_key_path": generated["private_key_path"],
    ], environment: env)
  let config = try Configuration.load(environment: env)
  #expect(config.values["apple_ads"] == .object(ads))
  #expect(config.credentialStatus("app_store_connect") == "configured_unverified")
  let configURL = CredentialSetup.configURL(environment: env)
  let before = try Data(contentsOf: configURL)
  var invalid = ads
  invalid["private_key_path"] = .string(dir.appendingPathComponent("missing.p8").path)
  #expect(throws: ScopeError.self) {
    try CredentialSetup.save(provider: "apple_ads", fields: invalid, environment: env)
  }
  #expect(try Data(contentsOf: configURL) == before)
  let permissions =
    try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
  #expect(permissions?.intValue == 0o600)
  try Configuration.checkPrivateFile(keyURL)
}
