//
//  NetworkClient.swift
//  PerfectNetworkCalling
//

import Foundation

/// Sends HTTP requests and decodes their responses.
///
/// Create one client per API and share it across your app. The client is `Sendable` and safe
/// to use from any task or actor.
///
/// ```swift
/// let client = NetworkClient(configuration: .init(baseURL: URL(string: "https://api.example.com")!))
///
/// let user: User = try await client.get("/users/1")
/// let created: User = try await client.post("/users", body: NewUser(name: "Ada"))
/// let updated: User = try await client.put("/users/1", body: user)
/// let patched: User = try await client.patch("/users/1", body: ["name": "Ada L."])
/// ```
///
/// What the client does for every request:
/// - **Timeouts:** each attempt is limited by ``Endpoint/timeout`` or ``NetworkConfiguration/timeout``.
/// - **Retries:** failed attempts are retried according to the ``RetryPolicy``.
/// - **Cancellation:** cancelling the calling `Task` cancels the request, including during a
///   retry delay. You can also use ``cancelAll()``, ``cancel(key:)`` and ``RequestToken``.
/// - **Errors:** every failure is thrown as a ``NetworkError`` with a readable message.
/// - **Interceptors:** every attempt runs through ``NetworkConfiguration/interceptors``.
///
/// Network and decoding work runs off the main actor, so calling the client from a
/// `@MainActor` view model never blocks the UI.
public final class NetworkClient: Sendable {
    /// The client's settings.
    public let configuration: NetworkConfiguration

    /// The session used to send requests.
    public let session: URLSession

    private let registry = TaskRegistry()
    private let deduplicator = RequestDeduplicator()

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - configuration: The client's settings.
    ///   - session: The session to send requests with. If `nil`, the client creates one with
    ///     ``NetworkConfiguration/timeout`` and ``NetworkConfiguration/resourceTimeout``.
    public init(configuration: NetworkConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
            sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
            sessionConfiguration.waitsForConnectivity = false
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    /// Creates a client with default settings.
    ///
    /// - Parameter baseURL: The URL every endpoint path is appended to.
    public convenience init(baseURL: URL) {
        self.init(configuration: NetworkConfiguration(baseURL: baseURL))
    }

    // MARK: - Core

    /// Sends a request and decodes the response.
    ///
    /// ```swift
    /// let endpoint = Endpoint.get("/users", query: ["page": "2"], timeout: 10)
    /// let users = try await client.request(endpoint, as: [User].self)
    /// ```
    ///
    /// Ask for ``EmptyResponse`` when you don't need the body, or `Data` for the raw bytes.
    ///
    /// - Parameters:
    ///   - endpoint: The request to send.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``: an HTTP-status case for a non-`2xx` response,
    ///   ``NetworkError/decodingFailed(_:)`` if the body doesn't match `type`,
    ///   ``NetworkError/timedOut``, ``NetworkError/cancelled``, or a connectivity case.
    @concurrent
    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        try await tracked(endpoint) { [self] in
            let (data, response) = try await fetch(endpoint)
            return try decode(T.self, from: data, response: response)
        }
    }

    /// Sends a request and returns the raw body and response without decoding.
    ///
    /// - Parameter endpoint: The request to send.
    /// - Returns: The response body and the HTTP response.
    /// - Throws: A ``NetworkError``. Non-`2xx` responses are thrown as their HTTP-status case.
    @concurrent
    public func requestData(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        try await tracked(endpoint) { [self] in
            try await fetch(endpoint)
        }
    }

    // MARK: - HTTP verbs

    /// Sends a `GET` request and decodes the response.
    ///
    /// ```swift
    /// let user: User = try await client.get("/users/1")
    /// let page = try await client.get("/users", query: ["page": "2"], timeout: 10, as: [User].self)
    /// ```
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``.
    @concurrent
    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await request(.get(path, query: query, headers: headers, timeout: timeout, retry: retry), as: type)
    }

    /// Sends a `POST` request with a JSON body and decodes the response.
    ///
    /// ```swift
    /// let created: User = try await client.post("/users", body: NewUser(name: "Ada"))
    /// ```
    ///
    /// - Important: `POST` is not retried unless the retry policy has
    ///   ``RetryPolicy/retryNonIdempotent`` set to `true`.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: The value encoded as the JSON body.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``, including ``NetworkError/encodingFailed(_:)`` if `body` can't be encoded.
    @concurrent
    public func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String,
        body: Body,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await request(.post(path, body: body, query: query, headers: headers, timeout: timeout, retry: retry), as: type)
    }

    /// Sends a `PUT` request with a JSON body and decodes the response.
    ///
    /// ```swift
    /// let saved: User = try await client.put("/users/1", body: user)
    /// ```
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: The value encoded as the JSON body.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``, including ``NetworkError/encodingFailed(_:)`` if `body` can't be encoded.
    @concurrent
    public func put<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String,
        body: Body,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await request(.put(path, body: body, query: query, headers: headers, timeout: timeout, retry: retry), as: type)
    }

    /// Sends a `PATCH` request with a JSON body and decodes the response.
    ///
    /// ```swift
    /// let patched: User = try await client.patch("/users/1", body: ["name": "Ada L."])
    /// ```
    ///
    /// - Important: `PATCH` is not retried unless the retry policy has
    ///   ``RetryPolicy/retryNonIdempotent`` set to `true`.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: The value encoded as the JSON body.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``, including ``NetworkError/encodingFailed(_:)`` if `body` can't be encoded.
    @concurrent
    public func patch<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String,
        body: Body,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await request(.patch(path, body: body, query: query, headers: headers, timeout: timeout, retry: retry), as: type)
    }

    /// Sends a `DELETE` request and decodes the response.
    ///
    /// ```swift
    /// let _: EmptyResponse = try await client.delete("/users/1")
    /// ```
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    ///   - type: The type to decode the response into. Use ``EmptyResponse`` to ignore the body.
    /// - Returns: The decoded response.
    /// - Throws: A ``NetworkError``.
    @concurrent
    public func delete<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil,
        as type: T.Type = EmptyResponse.self
    ) async throws -> T {
        try await request(.delete(path, query: query, headers: headers, timeout: timeout, retry: retry), as: type)
    }

    // MARK: - Multiple requests

    /// Sends several requests at the same time and returns their results in the same order.
    ///
    /// If any request fails, the others are cancelled and the error is thrown.
    ///
    /// ```swift
    /// let ids = [1, 2, 3]
    /// let users = try await client.requestAll(ids.map { .get("/users/\($0)") }, as: User.self)
    /// ```
    ///
    /// For requests that return different types, use `async let` instead:
    ///
    /// ```swift
    /// async let profile: Profile = client.get("/me")
    /// async let feed: [Post] = client.get("/feed")
    /// let (me, posts) = try await (profile, feed)
    /// ```
    ///
    /// - Parameters:
    ///   - endpoints: The requests to send.
    ///   - type: The type to decode each response into.
    ///   - maxConcurrent: The most requests in flight at once, or `nil` for no limit.
    /// - Returns: The decoded responses, in the order of `endpoints`.
    /// - Throws: The first ``NetworkError`` that occurs.
    @concurrent
    public func requestAll<T: Decodable & Sendable>(
        _ endpoints: [Endpoint],
        as type: T.Type = T.self,
        maxConcurrent: Int? = nil
    ) async throws -> [T] {
        guard !endpoints.isEmpty else { return [] }
        let limit = max(1, min(maxConcurrent ?? endpoints.count, endpoints.count))
        do {
            return try await withThrowingTaskGroup(of: (Int, T).self) { group in
                var results = [T?](repeating: nil, count: endpoints.count)
                var nextIndex = 0
                while nextIndex < limit {
                    let index = nextIndex, endpoint = endpoints[index]
                    group.addTask { (index, try await self.request(endpoint, as: T.self)) }
                    nextIndex += 1
                }
                while let (index, value) = try await group.next() {
                    results[index] = value
                    if nextIndex < endpoints.count {
                        let index = nextIndex, endpoint = endpoints[index]
                        group.addTask { (index, try await self.request(endpoint, as: T.self)) }
                        nextIndex += 1
                    }
                }
                return results.compactMap { $0 }
            }
        } catch {
            throw NetworkError.from(error)
        }
    }

    /// Sends several requests at the same time and returns every outcome, in the same order.
    ///
    /// Unlike ``requestAll(_:as:maxConcurrent:)``, a failure doesn't cancel the other requests,
    /// and this method never throws.
    ///
    /// ```swift
    /// let results = await client.requestAllSettled(ids.map { .get("/users/\($0)") }, as: User.self)
    /// for case .success(let user) in results { print(user.name) }
    /// ```
    ///
    /// - Parameters:
    ///   - endpoints: The requests to send.
    ///   - type: The type to decode each response into.
    ///   - maxConcurrent: The most requests in flight at once, or `nil` for no limit.
    /// - Returns: The result of each request, in the order of `endpoints`.
    @concurrent
    public func requestAllSettled<T: Decodable & Sendable>(
        _ endpoints: [Endpoint],
        as type: T.Type = T.self,
        maxConcurrent: Int? = nil
    ) async -> [Result<T, NetworkError>] {
        guard !endpoints.isEmpty else { return [] }
        let limit = max(1, min(maxConcurrent ?? endpoints.count, endpoints.count))
        return await withTaskGroup(of: (Int, Result<T, NetworkError>).self) { group in
            var results = [Result<T, NetworkError>](repeating: .failure(.cancelled), count: endpoints.count)
            var nextIndex = 0
            while nextIndex < limit {
                let index = nextIndex, endpoint = endpoints[index]
                group.addTask { (index, await self.result(of: endpoint, as: T.self)) }
                nextIndex += 1
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if nextIndex < endpoints.count {
                    let index = nextIndex, endpoint = endpoints[index]
                    group.addTask { (index, await self.result(of: endpoint, as: T.self)) }
                    nextIndex += 1
                }
            }
            return results
        }
    }

    // MARK: - Completion handlers

    /// Sends a request and calls `completion` with the result. Use this from code that
    /// doesn't use `async`/`await`.
    ///
    /// ```swift
    /// let token = client.send(.get("/users/1"), as: User.self) { result in
    ///     switch result {
    ///     case .success(let user): self.show(user)
    ///     case .failure(let error): self.show(error.errorDescription)
    ///     }
    /// }
    /// // Later, if needed:
    /// token.cancel()
    /// ```
    ///
    /// - Note: `completion` runs on the main queue by default, and is always called exactly
    ///   once, with ``NetworkError/cancelled`` if the request was cancelled.
    ///
    /// - Parameters:
    ///   - endpoint: The request to send.
    ///   - type: The type to decode the response into.
    ///   - callbackQueue: The queue `completion` runs on. Defaults to `.main`.
    ///   - completion: Called with the decoded response or the error.
    /// - Returns: A token that cancels the request.
    @discardableResult
    public func send<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self,
        callbackQueue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<T, NetworkError>) -> Void
    ) -> RequestToken {
        let task = Task { [self] in
            let result = await result(of: endpoint, as: T.self)
            callbackQueue.async { completion(result) }
        }
        return RequestToken(task: task)
    }

    // MARK: - Cancellation

    /// Cancels every in-flight request sent by this client. Each throws ``NetworkError/cancelled``.
    public func cancelAll() async {
        await registry.cancelAll()
    }

    /// Cancels the in-flight request with the given ``Endpoint/cancellationKey``.
    ///
    /// - Parameter key: The cancellation key.
    public func cancel(key: String) async {
        await registry.cancel(key: key)
    }

    /// The number of requests in flight.
    public var activeRequestCount: Int {
        get async { await registry.count }
    }

    // MARK: - Internals

    @concurrent
    private func result<T: Decodable & Sendable>(of endpoint: Endpoint, as type: T.Type) async -> Result<T, NetworkError> {
        do {
            return .success(try await request(endpoint, as: type))
        } catch {
            return .failure(NetworkError.from(error))
        }
    }

    /// Runs `operation` in its own task that the registry can cancel, and passes on
    /// cancellation of the calling task.
    private func tracked<T: Sendable>(
        _ endpoint: Endpoint,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        let task = Task { try await operation() }
        // Register before awaiting the result, so `remove` always runs after `register`.
        await registry.register(id, key: endpoint.cancellationKey) { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        await registry.remove(id, key: endpoint.cancellationKey)
        do {
            return try result.get()
        } catch {
            throw NetworkError.from(error)
        }
    }

    @concurrent
    private func fetch(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        guard endpoint.deduplicate, endpoint.method == .get else {
            return try await performWithRetries(endpoint)
        }
        let request = try makeRequest(for: endpoint)
        let headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let key = "\(endpoint.method.rawValue) \(request.url?.absoluteString ?? "") \(headers.joined(separator: "&"))"
        return try await deduplicator.run(key: key) { [self] in
            try await performWithRetries(endpoint)
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        try endpoint.urlRequest(
            baseURL: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultTimeout: configuration.timeout,
            encoder: configuration.encoder
        )
    }

    @concurrent
    private func performWithRetries(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let policy = endpoint.retryPolicy ?? configuration.retryPolicy
        let interceptors = configuration.interceptors
        let clock = ContinuousClock()
        var attempt = 1
        var policyRetries = 0
        var interceptorRetries = 0

        while true {
            try Task.checkCancellation()

            var request = try makeRequest(for: endpoint)
            do {
                for interceptor in interceptors {
                    request = try await interceptor.adapt(request, for: endpoint)
                }
            } catch {
                throw NetworkError.from(error)
            }
            for interceptor in interceptors {
                await interceptor.willSend(request, attempt: attempt)
            }

            let start = clock.now
            let failure: NetworkError
            do {
                let (data, response) = try await send(request)
                let duration = clock.now - start
                for interceptor in interceptors {
                    await interceptor.didReceive(response, data: data, for: request, duration: duration)
                }
                guard let error = NetworkError.from(HTTPErrorResponse(response: response, data: data)) else {
                    return (data, response)
                }
                failure = error
            } catch {
                failure = NetworkError.from(error)
            }

            let duration = clock.now - start
            for interceptor in interceptors {
                await interceptor.didFail(with: failure, for: request, attempt: attempt, duration: duration)
            }
            if failure == .cancelled || Task.isCancelled {
                throw NetworkError.cancelled
            }

            if interceptorRetries < configuration.maxInterceptorRetries,
               let delay = await interceptorRetryDelay(interceptors, request: request, error: failure, attempt: attempt) {
                interceptorRetries += 1
                attempt += 1
                if delay > .zero { try await Task.sleep(for: delay) }
                continue
            }

            if policyRetries < policy.maxRetries, policy.shouldRetry(failure, method: endpoint.method) {
                policyRetries += 1
                attempt += 1
                // Throws CancellationError if the task is cancelled while waiting.
                try await Task.sleep(for: policy.delay(forRetry: policyRetries, after: failure))
                continue
            }

            throw failure
        }
    }

    /// Asks each interceptor whether to retry. Returns the delay of the first one that says yes.
    private func interceptorRetryDelay(
        _ interceptors: [any NetworkInterceptor],
        request: URLRequest,
        error: NetworkError,
        attempt: Int
    ) async -> Duration? {
        for interceptor in interceptors {
            switch await interceptor.retryDecision(for: request, dueTo: error, attempt: attempt) {
            case .doNotRetry: continue
            case .retry: return .zero
            case .retryAfter(let delay): return delay
            }
        }
        return nil
    }

    /// Sends one attempt, limited to the request's timeout.
    ///
    /// `URLRequest.timeoutInterval` only limits the time *between* packets, so a slow
    /// download could run for much longer. The deadline here limits the whole attempt.
    @concurrent
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let timeout = request.timeoutInterval
        let session = session
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
            group.addTask {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                return (data, httpResponse)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw NetworkError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw NetworkError.timedOut }
            return first
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        if let empty = EmptyResponse() as? T { return empty }
        if let raw = data as? T { return raw }
        guard !data.isEmpty else {
            throw NetworkError.decodingFailed("The response body was empty, but \(T.self) was expected.")
        }
        do {
            return try configuration.decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.decodingFailed(NetworkError.describe(error))
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }
}
