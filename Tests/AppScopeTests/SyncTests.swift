import Foundation
import MCP
import Testing

@testable import AppScopeCore

actor ScriptedHTTP: HTTPTransport {
  var replies: [(Data, Int)]
  var requests: [URLRequest] = []
  init(_ replies: [(Data, Int)]) { self.replies = replies }
  func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
    requests.append(request)
    guard !replies.isEmpty else { throw ScopeError("unexpected_request", "Unexpected request") }
    let reply = replies.removeFirst()
    return (reply.0, reply.1, [:])
  }
}
func encoded(_ value: JSON) throws -> (Data, Int) { (try value.encoded(), 200) }

@Test func syncDownloadsAllSegmentsWithoutSendingBearerToStorage() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let today = day()
  let first = Data((downloadHeader + "\(today)\t12\tUS\tSearch\tFirst-time Download\t10\n").utf8)
  let second = Data((downloadHeader + "\(today)\t12\tUS\tBrowse\tFirst-time Download\t5\n").utf8)
  let transport = try ScriptedHTTP([
    encoded(["data": [["id": "request", "attributes": ["accessType": "ONGOING"]]]]),
    encoded(["data": [["id": "report", "attributes": ["name": "App Store Downloads"]]]]),
    encoded(["data": [["id": "instance", "attributes": ["processingDate": .string(today)]]]]),
    encoded([
      "data": [
        ["attributes": ["url": "https://reports.apple.com/one", "sizeInBytes": .int(first.count)]],
        [
          "attributes": ["url": "https://reports.apple.com/two", "sizeInBytes": .int(second.count)]
        ],
      ]
    ]),
    (first, 200), (second, 200),
  ])
  let database = try Database(directory: dir)
  let connect = AppStoreConnect(
    config: try testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0),
    database: database)
  let result = try await connect.sync(app: "12")
  #expect(result["instances_imported"].intValue == 1)
  let rows = try await database.list("analytics")
  #expect(rows.count == 1)
  #expect(rows[0]["rows"].list.count == 2)
  let requests = await transport.requests
  #expect(requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
  #expect(requests[4].value(forHTTPHeaderField: "Authorization") == nil)
  #expect(requests[5].value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func failedFinalSegmentDoesNotCommitPartialInstance() async throws {
  let dir = try scratch()
  defer { try? FileManager.default.removeItem(at: dir) }
  let today = day()
  let first = Data((downloadHeader + "\(today)\t12\tUS\tSearch\tFirst-time Download\t10\n").utf8)
  let transport = try ScriptedHTTP([
    encoded(["data": [["id": "request", "attributes": ["accessType": "ONGOING"]]]]),
    encoded(["data": [["id": "report", "attributes": ["name": "App Store Downloads"]]]]),
    encoded(["data": [["id": "instance", "attributes": ["processingDate": .string(today)]]]]),
    encoded([
      "data": [
        ["attributes": ["url": "https://reports.apple.com/one"]],
        ["attributes": ["url": "https://reports.apple.com/two"]],
      ]
    ]),
    (first, 200), (Data("secret-provider-error".utf8), 403),
  ])
  let database = try Database(directory: dir)
  let connect = AppStoreConnect(
    config: try testCredentials(dir), http: HTTP(transport: transport, searchInterval: 0),
    database: database)
  await #expect(throws: ScopeError.self) { try await connect.sync(app: "12") }
  #expect(try await database.list("analytics").isEmpty)
  #expect(try await database.list("imported_instance").isEmpty)
}
