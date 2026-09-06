import CryptoKit
import Darwin
import Foundation
import MCP

enum PrivateFile {
  static func write(_ data: Data, to url: URL, replace: Bool) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      guard replace else {
        throw ScopeError("file_exists", "A key file already exists. It will not be replaced.")
      }
      try Configuration.checkPrivateFile(url)
    }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".appscope-\(UUID().uuidString).tmp")
    let descriptor = open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw ScopeError("setup_error", "Cannot create a private temporary configuration file.")
    }
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: temporary)
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else {
          throw ScopeError("setup_error", "Cannot write private configuration.")
        }
        offset += count
      }
    }
    guard fsync(descriptor) == 0 else {
      throw ScopeError("setup_error", "Cannot persist private configuration.")
    }
    if replace {
      guard rename(temporary.path, url.path) == 0 else {
        throw ScopeError("setup_error", "Cannot replace local configuration.")
      }
    } else {
      // link is atomic and fails if another creator won the destination name.
      guard link(temporary.path, url.path) == 0 else {
        throw ScopeError("file_exists", "A key file already exists or cannot be created.")
      }
    }
  }
}

public enum CredentialSetup {
  public static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> URL
  {
    if let path = environment["APPSCOPE_CONFIG"] { return URL(fileURLWithPath: path) }
    let directory =
      environment["APPSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/AppScope")
    return directory.appendingPathComponent("config.json")
  }
  public static func fields(for provider: String) throws -> [String] {
    switch provider {
    case "apple_ads":
      return ["client_id", "team_id", "key_id", "ad_account_id", "private_key_path"]
    case "app_store_connect": return ["issuer_id", "key_id", "private_key_path"]
    default: throw ScopeError("invalid_provider", "Choose apple-ads or app-store-connect.")
    }
  }
  public static func save(
    provider: String, fields: [String: JSON],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let required = try Self.fields(for: provider)
    guard Set(fields.keys) == Set(required),
      required.allSatisfy({
        guard let text = fields[$0]?.stringValue else { return false }
        return !text.isEmpty && text.count <= 4096
          && text.rangeOfCharacter(from: .controlCharacters) == nil
          && !text.contains("PRIVATE KEY")
      })
    else {
      throw ScopeError(
        "invalid_credentials",
        "Every required identifier and a local private-key path must be supplied.")
    }
    let path = configURL(environment: environment)
    try FileManager.default.createDirectory(
      at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let lock: RefreshLock
    do {
      lock = try RefreshLock(
        directory: path.deletingLastPathComponent(), app: "configuration", country: "local")
    } catch {
      throw ScopeError(
        "configuration_busy",
        "Cannot lock configuration. Finish any other setup process and check directory access.")
    }
    defer { lock.release() }
    let old = try Configuration.load(environment: environment)
    var values = old.values.objectValue ?? [:]
    var normalized = fields
    let keyPath = (fields["private_key_path"]!.text as NSString).expandingTildeInPath
    normalized["private_key_path"] = .string(URL(fileURLWithPath: keyPath).standardizedFileURL.path)
    values[provider] = .object(normalized)
    let candidate = Configuration(directory: old.directory, values: .object(values))
    if provider == "apple_ads" { _ = try Validate.appID(fields["ad_account_id"]!.text) }
    // Offline key-format/permission check; the JWT is never returned or logged.
    _ = try candidate.signJWT(provider)
    try PrivateFile.write(try candidate.values.encoded(pretty: true), to: path, replace: true)
  }
  public static func generateAdsKey(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> JSON {
    let config = try Configuration.load(environment: environment)
    try FileManager.default.createDirectory(
      at: config.directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let keyPath = config.directory.appendingPathComponent("apple-ads-private.p8")
    let publicPath = config.directory.appendingPathComponent("apple-ads-public.pem")
    guard !FileManager.default.fileExists(atPath: keyPath.path),
      !FileManager.default.fileExists(atPath: publicPath.path)
    else {
      throw ScopeError(
        "file_exists",
        "Apple Ads key files already exist in the data directory. Existing keys are preserved.")
    }
    let key = P256.Signing.PrivateKey()
    try PrivateFile.write(Data(key.pemRepresentation.utf8), to: keyPath, replace: false)
    // If public-key creation fails, retain the generated private key so it is not lost.
    try PrivateFile.write(
      Data(key.publicKey.pemRepresentation.utf8), to: publicPath, replace: false)
    return [
      "private_key_path": .string(keyPath.path), "public_key_path": .string(publicPath.path),
      "public_key": .string(key.publicKey.pemRepresentation),
      "next_step":
        "Give Apple only this public key when creating an Ads API client. Then run appscope configure apple-ads. Private key bytes are never printed.",
    ]
  }
}

extension AppScope {
  func checkConnections(app: String, country: String) async throws -> JSON {
    var checks: [String: JSON] = [:]
    for name in ["public_search", "apple_ads", "app_store_connect"] {
      try Task.checkCancellation()
      if name != "public_search" && config.credentialStatus(name) == "not_configured" {
        checks[name] = ["status": "not_configured"]
        continue
      }
      do {
        switch name {
        case "public_search": _ = try await storefront.lookup(app, country: country)
        case "apple_ads":
          let result = try await ads.suggestions(app: app, country: country, seeds: [], offset: 0)
          checks[name] = ["suggestions_returned": .int(result["suggestions"].list.count)]
        default:
          let result = try await connect.get(
            endpoint("https://api.appstoreconnect.apple.com/v1/apps/\(app)"))
          guard result["data"]["id"].text == app else {
            throw ScopeError("app_access_unverified", "Apple did not confirm access to this app.")
          }
          let requests = try await connect.pages(
            "apps/\(app)/analyticsReportRequests", query: ["limit": "200"])
          let ongoing = requests.contains {
            $0["attributes"]["accessType"].text == "ONGOING"
              && $0["attributes"]["stoppedDueToInactivity"].boolValue != true
          }
          checks[name] = [
            "ongoing_reports_enabled": .bool(ongoing),
            "next_step": .string(
              ongoing
                ? "Run app_performance to validate report downloads and coverage."
                : "An Admin must enable ongoing reports once with the CLI."),
          ]
        }
        checks[name] = (checks[name] ?? [:]).setting([
          "status": "ok", "checked_at": .string(timestamp()),
        ])
      } catch is CancellationError { throw CancellationError() } catch {
        let error =
          (error as? ScopeError)
          ?? ScopeError("check_failed", "The connection check could not finish. Check local setup.")
        checks[name] = error.json.setting(["checked_at": .string(timestamp())])
      }
    }
    return [
      "app_id": .string(app), "country": .string(country), "checks": .object(checks),
      "status": .string(
        checks.values.contains { $0["status"].text == "error" } ? "partial" : "checked"),
      "scope":
        "Read-only live app lookup, Ads suggestion request, and App Store Connect app/report-request access. No reports are enabled or downloaded. Does not prove device-rank accuracy, complete keyword coverage or analytics reconciliation.",
    ]
  }
}
