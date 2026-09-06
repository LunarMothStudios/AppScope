import CryptoKit
import Foundation
import MCP

public struct Configuration: Sendable {
  public let directory: URL
  public let values: JSON
  public init(directory: URL, values: JSON = .object([:])) {
    self.directory = directory
    self.values = values
  }
  public static func load(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> Configuration
  {
    let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/AppScope")
    let directory =
      environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? defaultDirectory
    let path =
      environment["APPSCOPE_CONFIG"].map { URL(fileURLWithPath: $0) }
      ?? directory.appendingPathComponent("config.json")
    guard FileManager.default.fileExists(atPath: path.path) else {
      return Configuration(directory: directory)
    }
    try checkPrivateFile(path)
    do {
      return Configuration(directory: directory, values: try JSON.decode(Data(contentsOf: path)))
    } catch {
      throw ScopeError(
        "invalid_config", "AppScope configuration must be valid JSON. Run appscope setup.")
    }
  }
  public func credentialStatus(_ name: String) -> String {
    let required =
      name == "apple_ads"
      ? ["client_id", "team_id", "key_id", "private_key_path", "ad_account_id"]
      : ["issuer_id", "key_id", "private_key_path"]
    return required.allSatisfy { !values[name][$0].text.isEmpty }
      ? "configured_unverified" : "not_configured"
  }
  public func credentials(_ name: String) throws -> JSON {
    guard credentialStatus(name) == "configured_unverified" else {
      throw ScopeError(
        "credentials_missing",
        "Configure \(name) locally with appscope setup. Public searches still work.")
    }
    return values[name]
  }
  public static func checkPrivateFile(_ url: URL) throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
      throw ScopeError(
        "unsafe_permissions",
        "Credential files must be readable only by their owner. Use chmod 600 on the configuration and private key files."
      )
    }
    guard attrs[.type] as? FileAttributeType == .typeRegular else {
      throw ScopeError("unsafe_file", "Credentials must be regular files.")
    }
  }
  public func signJWT(_ provider: String, now: Date = Date()) throws -> String {
    let settings = try credentials(provider)
    let keyURL = URL(
      fileURLWithPath: (settings["private_key_path"].text as NSString).expandingTildeInPath)
    do {
      try Self.checkPrivateFile(keyURL)
      let key = try P256.Signing.PrivateKey(
        pemRepresentation: String(contentsOf: keyURL, encoding: .utf8))
      let seconds = Int(now.timeIntervalSince1970)
      let header: JSON = ["alg": "ES256", "kid": settings["key_id"], "typ": "JWT"]
      let claims: JSON =
        provider == "apple_ads"
        ? [
          "iss": settings["team_id"], "sub": settings["client_id"],
          "aud": "https://appleid.apple.com", "iat": .int(seconds), "exp": .int(seconds + 3600),
        ]
        : [
          "iss": settings["issuer_id"], "aud": "appstoreconnect-v1", "iat": .int(seconds),
          "exp": .int(seconds + 900),
        ]
      let signingInput = try header.encoded().base64URL + "." + claims.encoded().base64URL
      let signature = try key.signature(for: Data(signingInput.utf8))
      return signingInput + "." + signature.rawRepresentation.base64URL
    } catch let error as ScopeError { throw error } catch {
      throw ScopeError(
        "invalid_private_key",
        "Unable to read or sign with the configured P-256 private key. Check its path, format, and permissions."
      )
    }
  }
}
extension Data {
  var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
}
