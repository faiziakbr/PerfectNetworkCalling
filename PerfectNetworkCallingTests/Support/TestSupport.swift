//
//  TestSupport.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

/// A value protected by a lock, safe to share between tasks.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    var current: Value { withLock { $0 } }
}

let testBaseURL = URL(string: "https://api.test.com")!

/// A retry policy with no delays, so retry tests run fast.
func instantRetry(_ maxRetries: Int, nonIdempotent: Bool = false) -> RetryPolicy {
    RetryPolicy(maxRetries: maxRetries, baseDelay: 0, maxDelay: 0, jitter: 0, retryNonIdempotent: nonIdempotent)
}

/// Builds a client whose session sends every request to `MockURLProtocol`.
func makeClient(
    timeout: TimeInterval = 5,
    retryPolicy: RetryPolicy = .none,
    interceptors: [any NetworkInterceptor] = [],
    maxInterceptorRetries: Int = 1
) -> NetworkClient {
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    let configuration = NetworkConfiguration(
        baseURL: testBaseURL,
        timeout: timeout,
        retryPolicy: retryPolicy,
        interceptors: interceptors,
        maxInterceptorRetries: maxInterceptorRetries
    )
    return NetworkClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
}

/// Runs `body` and returns the `NetworkError` it throws, or `nil` if it succeeds.
func networkError(_ body: () async throws -> Void) async -> NetworkError? {
    do {
        try await body()
        return nil
    } catch let error as NetworkError {
        return error
    } catch {
        Issue.record("Expected NetworkError, got \(type(of: error)): \(error)")
        return nil
    }
}

// MARK: - Models

struct User: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

struct NewUser: Codable, Sendable, Equatable {
    let name: String
}

func userJSON(_ id: Int, _ name: String = "Ada") -> String {
    #"{"id":\#(id),"name":"\#(name)"}"#
}

// MARK: - Interceptors

/// Records every hook call as a string, in order.
struct SpyInterceptor: NetworkInterceptor {
    let events = Locked<[String]>([])
    var addHeader: (field: String, value: String)?

    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
        events.withLock { $0.append("adapt") }
        var request = request
        if let addHeader { request.setValue(addHeader.value, forHTTPHeaderField: addHeader.field) }
        return request
    }

    func willSend(_ request: URLRequest, attempt: Int) async {
        events.withLock { $0.append("willSend(\(attempt))") }
    }

    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) async {
        events.withLock { $0.append("didReceive(\(response.statusCode))") }
    }

    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async {
        events.withLock { $0.append("didFail(\(attempt))") }
    }
}

/// A token provider that counts refreshes. Refreshing takes `refreshDelay`.
actor CountingTokenProvider: AuthTokenProvider {
    private var current: String?
    private(set) var refreshCount = 0
    private let newToken: String
    private let refreshDelay: Duration
    private let failRefresh: Bool

    init(initial: String?, newToken: String = "new-token", refreshDelay: Duration = .milliseconds(100), failRefresh: Bool = false) {
        self.current = initial
        self.newToken = newToken
        self.refreshDelay = refreshDelay
        self.failRefresh = failRefresh
    }

    func token() async throws -> String? { current }

    func refreshToken() async throws -> String {
        refreshCount += 1
        try await Task.sleep(for: refreshDelay)
        if failRefresh { throw URLError(.userAuthenticationRequired) }
        current = newToken
        return newToken
    }
}

/// A parent suite that runs every test using `MockURLProtocol` one at a time,
/// because the mock's state is shared.
@Suite(.serialized)
struct MockedNetworkTests {}
