//
//  MockURLProtocol.swift
//  PerfectNetworkCallingTests
//

import Foundation

/// A canned response returned by ``MockURLProtocol``.
struct Stub: Sendable {
    var statusCode: Int = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var data: Data = Data()
    var delay: TimeInterval = 0
    var error: URLError.Code?

    static func json(_ json: String, status: Int = 200, delay: TimeInterval = 0, headers: [String: String] = [:]) -> Stub {
        var stub = Stub(statusCode: status, data: Data(json.utf8), delay: delay)
        stub.headers.merge(headers) { _, new in new }
        return stub
    }

    static func status(_ status: Int, body: String = "", delay: TimeInterval = 0, headers: [String: String] = [:]) -> Stub {
        json(body, status: status, delay: delay, headers: headers)
    }

    static func failure(_ code: URLError.Code, delay: TimeInterval = 0) -> Stub {
        Stub(delay: delay, error: code)
    }
}

/// Intercepts every request of a session and answers with stubs from a handler.
///
/// State is static, so tests that use it must run serially (see `MockedNetworkTests`).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> Stub

    private static let state = Locked<State>(State())

    private struct State {
        var handler: Handler?
        var requests: [URLRequest] = []
        var active = 0
        var peakActive = 0
    }

    private let lock = NSLock()
    private var workItem: DispatchWorkItem?
    private var isFinished = false

    // MARK: Test API

    static func reset(handler: @escaping Handler) {
        state.withLock { $0 = State(handler: handler) }
    }

    /// Answers requests in order with `stubs`. The last stub repeats.
    static func reset(sequence stubs: [Stub]) {
        let index = Locked(0)
        reset { _ in
            index.withLock { i in
                defer { i += 1 }
                return stubs[min(i, stubs.count - 1)]
            }
        }
    }

    static var requests: [URLRequest] { state.withLock { $0.requests } }
    static var requestCount: Int { state.withLock { $0.requests.count } }
    static var peakActive: Int { state.withLock { $0.peakActive } }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        recorded.httpBody = request.httpBody ?? Self.readBody(of: request)
        let handler = Self.state.withLock { state -> Handler? in
            state.requests.append(recorded)
            state.active += 1
            state.peakActive = max(state.peakActive, state.active)
            return state.handler
        }
        let stub = handler?(recorded) ?? Stub.status(500, body: #"{"message":"No stub"}"#)

        let item = DispatchWorkItem { [weak self] in self?.respond(with: stub) }
        lock.withLock { workItem = item }
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: item)
    }

    override func stopLoading() {
        lock.withLock { workItem?.cancel() }
        finish()
    }

    private func respond(with stub: Stub) {
        // Finish before notifying the client, so the next request never sees this one as active.
        guard finish() else { return }
        if let code = stub.error {
            client?.urlProtocol(self, didFailWithError: URLError(code))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Marks the request as finished. Returns `false` if it had already finished.
    @discardableResult
    private func finish() -> Bool {
        let firstTime = lock.withLock { () -> Bool in
            defer { isFinished = true }
            return !isFinished
        }
        if firstTime {
            Self.state.withLock { $0.active -= 1 }
        }
        return firstTime
    }

    private static func readBody(of request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
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
