import MCP
import Foundation
import CryptoKit
import CZlib

public enum Reports {
    public static let names = ["App Store Downloads", "App Store Discovery and Engagement", "App Store Purchases"]
    /// RFC-style quoting, including embedded tabs/newlines; unknown schemas fail closed.
    public static func parse(_ data: Data, report: String, appID: String) throws -> [JSON] {
        let bytes = try decompress(data)
        guard let text = String(data: bytes, encoding: .utf8) else { throw ScopeError("invalid_report", "The report is not UTF-8 text.") }
        var records: [[String]] = []; var row: [String] = []; var cell = ""; var quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
                else if quoted || cell.isEmpty { quoted.toggle() }
                else { cell.append(c) }
            } else if c == "\t" && !quoted { row.append(cell); cell = "" }
            else if c == "\n" && !quoted { row.append(cell); if row.contains(where: { !$0.isEmpty }) { records.append(row) }; row = []; cell = "" }
            else { cell.append(c) }
            i += 1
        }
        guard !quoted else { throw ScopeError("invalid_report", "Unclosed quote in report.") }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); records.append(row) }
        guard let first = records.first else { throw ScopeError("invalid_report", "The report has no header.") }
        let headers = first.map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespaces) }
        let required = ["Date", "App Apple Identifier", "Territory", "Source Type"] + (report == names[0] ? ["Download Type", "Counts"] : report == names[1] ? ["Event", "Page Type", "Counts"] : ["Sales in USD", "Proceeds in USD", "Purchases"])
        guard names.contains(report), Set(headers).count == headers.count, required.allSatisfy(headers.contains) else { throw ScopeError("unsupported_report_schema", "The report does not match Apple's documented standard analytics schema.") }
        return try records.dropFirst().map { cells in
            guard cells.count == headers.count else { throw ScopeError("invalid_report", "A report row has the wrong number of fields. The instance was not saved.") }
            let value = JSON.object(Dictionary(uniqueKeysWithValues: zip(headers, cells.map(JSON.string))))
            guard value["App Apple Identifier"].text == appID else { throw ScopeError("wrong_app_report", "The report contains data for a different app.") }
            _ = try Validate.date(value["Date"].text)
            for name in required where ["Counts", "Sales in USD", "Proceeds in USD", "Purchases"].contains(name) {
                guard let number = Double(value[name].text), number.isFinite, name != "Counts" || (number >= 0 && number.rounded() == number) else { throw ScopeError("invalid_report_number", "The report contains missing or invalid numeric data.") }
            }
            return value
        }
    }
    public static func decompress(_ data: Data) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { return data }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ScopeError("gzip_error", "Cannot initialize report decompression.") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            var output = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
                    stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress!; stream.avail_out = uInt(bytes.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                output.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                guard output.count <= 64 * 1024 * 1024 else { throw ScopeError("report_too_large", "Expanded report exceeds 64 MB.") }
                if status == Z_STREAM_END { break }
                guard status == Z_OK else { throw ScopeError("gzip_error", "Report gzip is truncated or invalid.") }
            }
            return output
        }
    }
    public static func summarize(_ records: [JSON], app: String, country: String, start: String, end: String) -> JSON {
        let selected = records.filter { $0["app_id"].text == app && $0["date"].text >= start && $0["date"].text <= end }
        var output: [String: JSON] = ["source": "app_store_connect", "app_id": .string(app), "country": .string(country), "start": .string(start), "end": .string(end)]
        var metrics: [String: JSON] = [:]; var coverage: [String: JSON] = [:]
        for report in names {
            let batches = selected.filter { $0["report"].text == report }
            let rows = batches.flatMap { $0["rows"].list }.filter { country == "all" || $0["Territory"].text.lowercased() == country }
            coverage[report] = ["dates_with_reports": .strings(batches.map { $0["date"].text }.sorted()), "latest_processing_date": batches.map { $0["processing_date"].text }.max().map(JSON.string) ?? .null, "matching_rows": .int(rows.count)]
            func sum(_ field: String, where predicate: (JSON) -> Bool = { _ in true }) -> JSON {
                guard !batches.isEmpty, !rows.isEmpty else { return .null }
                return .double(rows.filter(predicate).reduce(0) { $0 + (Double($1[field].text) ?? 0) })
            }
            if report == names[0] {
                metrics["first_time_downloads"] = sum("Counts") { $0["Download Type"].text.lowercased() == "first-time download" }
                metrics["redownloads"] = sum("Counts") { $0["Download Type"].text.lowercased() == "redownload" }
            } else if report == names[1] {
                metrics["impression_events"] = sum("Counts") { $0["Event"].text.lowercased() == "impression" }
                metrics["product_page_view_events"] = sum("Counts") { $0["Event"].text.lowercased() == "page view" && $0["Page Type"].text.lowercased() == "product page" }
            } else {
                metrics["sales_usd"] = sum("Sales in USD"); metrics["proceeds_usd"] = sum("Proceeds in USD")
            }
        }
        metrics["apple_conversion_rate"] = .null
        output["metrics"] = .object(metrics); output["coverage"] = .object(coverage)
        output["status"] = .string(selected.isEmpty ? "no_data" : "available")
        output["caveats"] = .strings(["Missing dates or country rows are unknown, not zero. Totals cover only listed report dates.", "Unique Counts and Paying Users are not summed across rows. Apple's conversion rate is not reconstructed from these segmented reports.", "Impression events exclude page views; they differ from the App Store Connect UI's impressions metric.", "App Store search includes Apple Ads traffic. Purchases are estimated USD sales/proceeds, not settled payouts.", "Daily downloads/purchases can lag two days; engagement can lag three. Later corrections replace earlier date batches."])
        return .object(output)
    }
}

public struct AppStoreConnect: Sendable {
    let config: Configuration
    let http: HTTP
    let database: Database
    public init(config: Configuration, http: HTTP, database: Database) { self.config = config; self.http = http; self.database = database }
    func get(_ url: URL) async throws -> JSON {
        guard url.scheme == "https", url.host == "api.appstoreconnect.apple.com", url.path.hasPrefix("/v1/") else { throw ScopeError("unsafe_url", "Refusing to send Apple credentials to an unexpected API URL.") }
        return try await http.json(url, headers: ["Authorization": "Bearer \(config.signJWT("app_store_connect"))"])
    }
    func pages(_ path: String, query: [String: String] = [:]) async throws -> [JSON] {
        var url: URL? = endpoint("https://api.appstoreconnect.apple.com/v1/" + path, query: query)
        var seen = Set<String>(); var rows: [JSON] = []
        while let next = url {
            guard seen.insert(next.absoluteString).inserted, seen.count <= 50 else { throw ScopeError("pagination_limit", "Apple report pagination is incomplete. Narrow the query before retrying.") }
            let response = try await get(next)
            guard let data = response["data"].arrayValue else { throw ScopeError("invalid_response", "Apple did not return a list of report resources.") }
            rows += data
            if response["links"]["next"] == .null { url = nil }
            else { guard let link = URL(string: response["links"]["next"].text) else { throw ScopeError("invalid_response", "Invalid pagination link.") }; url = link }
        }
        return rows
    }
    public func apps() async throws -> JSON { .array(try await pages("apps", query: ["limit": "200"])) }
    public static func validDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com") || host.hasSuffix(".amazonaws.com")
    }
    public func sync(app: String, days: Int = 35) async throws -> JSON {
        let requests = try await pages("apps/\(app)/analyticsReportRequests", query: ["limit": "200"])
        guard let ongoing = requests.first(where: { $0["attributes"]["accessType"].text == "ONGOING" && $0["attributes"]["stoppedDueToInactivity"].boolValue != true }) else {
            throw ScopeError("reports_not_enabled", "An Admin must enable ongoing reports once: appscope enable-reports APP_ID --confirm. Apple may take 24–48 hours to generate initial reports.")
        }
        let reports = try await pages("analyticsReportRequests/\(ongoing["id"].text)/reports", query: ["limit": "200"])
        var imported = 0; var available: [String] = []; let cutoff = dateOffset(day(), days: -days)
        for report in reports where Reports.names.contains(report["attributes"]["name"].text) {
            let name = report["attributes"]["name"].text; available.append(name)
            let instances = try await pages("analyticsReports/\(report["id"].text)/instances", query: ["filter[granularity]": "DAILY", "limit": "200"])
            for instance in instances.sorted(by: { $0["attributes"]["processingDate"].text < $1["attributes"]["processingDate"].text }) {
                let processed = instance["attributes"]["processingDate"].text
                _ = try Validate.date(processed)
                if processed < cutoff { continue }
                let cacheKey = "\(app)|\(report["id"].text)|\(instance["id"].text)"
                if try await database.get("imported_instance", cacheKey) != nil { continue }
                let segments = try await pages("analyticsReportInstances/\(instance["id"].text)/segments", query: ["limit": "200"])
                guard !segments.isEmpty else { throw ScopeError("report_not_ready", "A report instance has no downloadable segments yet.") }
                var rows: [JSON] = []
                for segment in segments {
                    let attributes = segment["attributes"]
                    guard let url = URL(string: attributes["url"].text), Self.validDownloadURL(url) else { throw ScopeError("unsafe_url", "Apple returned an unexpected report download URL.") }
                    // Signed download URLs receive no Apple API Authorization header.
                    let data = try await http.request(url)
                    if let size = attributes["sizeInBytes"].intValue, size != data.count { throw ScopeError("report_size_mismatch", "A downloaded report segment has the wrong size.") }
                    let checksum = attributes["checksum"].text.lowercased()
                    if !checksum.isEmpty {
                        let digest = checksum.count == 64 ? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() : Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
                        guard digest == checksum else { throw ScopeError("report_checksum_mismatch", "A report segment failed checksum verification.") }
                    }
                    rows += try Reports.parse(data, report: name, appID: app)
                }
                try await database.saveAnalytics(app: app, report: name, processingDate: processed, instanceID: instance["id"].text, rows: rows)
                try await database.put("imported_instance", cacheKey, ["imported_at": .string(timestamp())]); imported += 1
            }
        }
        return ["status": .string(available.isEmpty ? "pending" : "synced"), "instances_imported": .int(imported), "available_reports": .strings(available), "missing_reports": .strings(Reports.names.filter { !available.contains($0) }), "synced_at": .string(timestamp())]
    }
    /// CLI only; deliberately not exposed as an MCP tool.
    public func enableReports(app: String) async throws -> JSON {
        let existing = try await pages("apps/\(app)/analyticsReportRequests", query: ["limit": "200"])
        if existing.contains(where: { $0["attributes"]["accessType"].text == "ONGOING" && $0["attributes"]["stoppedDueToInactivity"].boolValue != true }) { return ["status": "already_enabled"] }
        return try await http.json(endpoint("https://api.appstoreconnect.apple.com/v1/analyticsReportRequests"), method: "POST", headers: ["Authorization": "Bearer \(config.signJWT("app_store_connect"))"], body: ["data": ["type": "analyticsReportRequests", "attributes": ["accessType": "ONGOING"], "relationships": ["app": ["data": ["type": "apps", "id": .string(app)]]]]])
    }
}
