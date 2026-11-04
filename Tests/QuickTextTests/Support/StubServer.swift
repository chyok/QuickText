import Foundation
@testable import QuickText

/// Serves canned HTTP responses to URLSessions built with `StubServer.sessionConfiguration()`.
/// Each server has its own host name, so tests can run in parallel.
final class StubServer: @unchecked Sendable {
    enum Reply {
        case json(status: Int, String)
        case failure(URLError.Code)
    }

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    private let lock = NSLock()
    private var reply: Reply
    private var captured: [(request: URLRequest, body: Data)] = []

    init(_ reply: Reply) {
        self.reply = reply
        StubURLProtocol.register(self)
    }

    deinit {
        StubURLProtocol.unregister(host)
    }

    var baseURL: URL { URL(string: "https://\(host)/v1")! }

    var requests: [(request: URLRequest, body: Data)] {
        lock.withLock { captured }
    }

    /// The last request's JSON body.
    var lastBody: [String: Any] {
        guard let body = requests.last?.body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    fileprivate func handle(_ request: URLRequest, body: Data) -> Reply {
        lock.withLock {
            captured.append((request, body))
            return reply
        }
    }
}

final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) {
        lock.withLock { servers[server.host] = server }
    }

    static func unregister(_ host: String) {
        lock.withLock { _ = servers.removeValue(forKey: host) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let server = Self.lock.withLock({ Self.servers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch server.handle(request, body: Self.body(of: request)) {
        case let .json(status, json):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    /// URLSession hands the body to protocols as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
