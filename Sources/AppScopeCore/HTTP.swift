import MCP
import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int, [String: String])
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}
public struct URLTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ScopeError("invalid_response", "The provider returned an invalid response.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 32 * 1024 * 1024 else { throw ScopeError("response_too_large", "The provider response exceeds the 32 MB limit.") }
            data.append(byte)
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in result[String(describing: field.key).lowercased()] = String(describing: field.value) }
        return (data, response.statusCode, headers)
    }
}
public actor HTTP {
    let transport: any HTTPTransport
    let interval: Double
    var nextSearch = Date.distantPast
    public init(transport: any HTTPTransport = URLTransport(), searchInterval: Double = 3.2) { self.transport = transport; self.interval = searchInterval }
    public func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, search: Bool = false, attempts: Int = 3) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { throw ScopeError("unsafe_url", "Only HTTPS provider URLs are allowed.") }
        if search {
            let reserved = max(Date(), nextSearch); nextSearch = reserved.addingTimeInterval(interval)
            let delay = reserved.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("AppScope/\(appScopeVersion)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        for attempt in 0..<attempts {
            do {
                let (data, status, responseHeaders) = try await transport.send(request)
                if (200..<300).contains(status) { return data }
                if status == 429 || (500...599).contains(status) {
                    if attempt + 1 < attempts {
                        let delay = min(15, max(1, Double(responseHeaders["retry-after"] ?? "") ?? pow(2, Double(attempt))))
                        try await Task.sleep(for: .seconds(delay)); continue
                    }
                }
                throw ScopeError("provider_http_\(status)", "Provider returned HTTP \(status). Check access, request parameters, or retry later. Response details are withheld to protect credentials.")
            } catch let error as ScopeError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch {
                if attempt + 1 == attempts { throw ScopeError("network_error", "The provider could not be reached. No observation was saved.") }
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw ScopeError("network_error", "Request failed.")
    }
    public func json(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: JSON? = nil, search: Bool = false) async throws -> JSON {
        var headers = headers
        if body != nil { headers["Content-Type"] = "application/json" }
        let data = try await request(url, method: method, headers: headers, body: try body?.encoded(), search: search)
        do { return try JSON.decode(data) }
        catch { throw ScopeError("invalid_response", "The provider did not return valid JSON. No observation was saved.") }
    }
}
public func endpoint(_ base: String, query: [String: String] = [:]) -> URL {
    var parts = URLComponents(string: base)!
    if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
    return parts.url!
}
