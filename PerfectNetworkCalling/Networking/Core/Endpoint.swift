//
//  Endpoint.swift
//  PerfectNetworkCalling
//

import Foundation

/// A description of a single HTTP request: where it goes, how it is sent, and how it behaves.
///
/// An endpoint is a plain value. It never touches the network itself. Pass it to
/// ``NetworkClient/request(_:as:)``, ``NetworkClient/requestAll(_:as:maxConcurrent:)`` or
/// ``NetworkClient/send(_:as:callbackQueue:completion:)`` to run it.
///
/// Settings on the endpoint override the client defaults from ``NetworkConfiguration``:
/// ``timeout`` overrides ``NetworkConfiguration/timeout``, ``retryPolicy`` overrides
/// ``NetworkConfiguration/retryPolicy``, and ``headers`` are merged over
/// ``NetworkConfiguration/defaultHeaders``.
///
/// ```swift
/// let endpoint = Endpoint.get("/search", query: ["q": "swift"], timeout: 5)
///     .cancelling(previousWithKey: "search")
/// let results: [Repo] = try await client.request(endpoint)
/// ```
public struct Endpoint: Sendable {
    /// The path appended to ``NetworkConfiguration/baseURL``, for example `"/users/1"`.
    ///
    /// If the path is an absolute URL (`"https://cdn.example.com/file.json"`), the base URL is ignored.
    public var path: String

    /// The HTTP method.
    public var method: HTTPMethod

    /// Query parameters. Keys are sorted when the URL is built, so the same endpoint always
    /// produces the same URL. A `+` in a value is encoded as `%2B`.
    public var query: [String: String]

    /// Headers for this request. They override ``NetworkConfiguration/defaultHeaders`` with the same name.
    public var headers: [String: String]

    /// The request body, or `nil` for no body.
    public var body: HTTPBody?

    /// The maximum time, in seconds, the whole request may take, or `nil` to use
    /// ``NetworkConfiguration/timeout``. Each retry attempt gets the full timeout again.
    public var timeout: TimeInterval?

    /// The retry policy for this request, or `nil` to use ``NetworkConfiguration/retryPolicy``.
    public var retryPolicy: RetryPolicy?

    /// Whether identical requests that are in flight at the same time share one network call.
    ///
    /// Only applies to `GET`. Requests count as identical when they have the same method,
    /// URL and headers. Each caller decodes the shared response on its own, and cancelling one
    /// caller doesn't affect the others.
    public var deduplicate: Bool

    /// A key that makes a new request cancel the previous in-flight request with the same key.
    ///
    /// Use it for "latest wins" calls such as search-as-you-type, so an older, slower response
    /// can never overwrite a newer one. The cancelled request throws ``NetworkError/cancelled``.
    public var cancellationKey: String?

    /// Creates an endpoint.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - method: The HTTP method. Defaults to `GET`.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - body: The request body.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retryPolicy: The retry policy, or `nil` for the client default.
    ///   - deduplicate: Whether identical in-flight `GET` requests share one network call.
    ///   - cancellationKey: A key that cancels the previous in-flight request with the same key.
    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: HTTPBody? = nil,
        timeout: TimeInterval? = nil,
        retryPolicy: RetryPolicy? = nil,
        deduplicate: Bool = false,
        cancellationKey: String? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.deduplicate = deduplicate
        self.cancellationKey = cancellationKey
    }

    // MARK: - Factories

    /// Creates a `GET` endpoint.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    /// - Returns: The endpoint.
    public static func get(
        _ path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil
    ) -> Endpoint {
        Endpoint(path: path, method: .get, query: query, headers: headers, timeout: timeout, retryPolicy: retry)
    }

    /// Creates a `POST` endpoint with a JSON body.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: A value encoded as JSON.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    /// - Returns: The endpoint.
    public static func post(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil
    ) -> Endpoint {
        Endpoint(path: path, method: .post, query: query, headers: headers, body: body.map(HTTPBody.json), timeout: timeout, retryPolicy: retry)
    }

    /// Creates a `PUT` endpoint with a JSON body.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: A value encoded as JSON.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    /// - Returns: The endpoint.
    public static func put(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil
    ) -> Endpoint {
        Endpoint(path: path, method: .put, query: query, headers: headers, body: body.map(HTTPBody.json), timeout: timeout, retryPolicy: retry)
    }

    /// Creates a `PATCH` endpoint with a JSON body.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - body: A value encoded as JSON.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    /// - Returns: The endpoint.
    public static func patch(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil
    ) -> Endpoint {
        Endpoint(path: path, method: .patch, query: query, headers: headers, body: body.map(HTTPBody.json), timeout: timeout, retryPolicy: retry)
    }

    /// Creates a `DELETE` endpoint.
    ///
    /// - Parameters:
    ///   - path: A path relative to the base URL, or an absolute URL.
    ///   - query: Query parameters.
    ///   - headers: Headers for this request only.
    ///   - timeout: The timeout in seconds, or `nil` for the client default.
    ///   - retry: The retry policy, or `nil` for the client default.
    /// - Returns: The endpoint.
    public static func delete(
        _ path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retry: RetryPolicy? = nil
    ) -> Endpoint {
        Endpoint(path: path, method: .delete, query: query, headers: headers, timeout: timeout, retryPolicy: retry)
    }

    // MARK: - Modifiers

    /// Returns a copy that shares one network call with identical in-flight `GET` requests.
    ///
    /// - Returns: The modified endpoint.
    public func deduplicated() -> Endpoint {
        var copy = self
        copy.deduplicate = true
        return copy
    }

    /// Returns a copy that cancels the previous in-flight request with the same key.
    ///
    /// - Parameter key: The cancellation key, for example `"search"`.
    /// - Returns: The modified endpoint.
    public func cancelling(previousWithKey key: String) -> Endpoint {
        var copy = self
        copy.cancellationKey = key
        return copy
    }

    // MARK: - Building the URLRequest

    /// Builds the `URLRequest` for this endpoint. Interceptors are not applied.
    ///
    /// - Parameters:
    ///   - baseURL: The URL that ``path`` is appended to.
    ///   - defaultHeaders: Headers added to every request. Headers in ``headers`` win.
    ///   - defaultTimeout: The timeout used when ``timeout`` is `nil`.
    ///   - encoder: The encoder for JSON bodies.
    /// - Returns: The request.
    /// - Throws: ``NetworkError/invalidURL(_:)`` if no valid URL can be built, or
    ///   ``NetworkError/encodingFailed(_:)`` if the body cannot be encoded.
    public func urlRequest(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        defaultTimeout: TimeInterval = 30,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> URLRequest {
        let url: URL
        if let absolute = URL(string: path), absolute.scheme != nil, absolute.host != nil {
            url = absolute
        } else if path.isEmpty {
            url = baseURL
        } else {
            url = baseURL.appending(path: path)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw NetworkError.invalidURL(path)
        }
        if !query.isEmpty {
            let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.queryItems = (components.queryItems ?? []) + items
            // URLComponents leaves "+" unencoded, but most servers decode it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let finalURL = components.url, finalURL.scheme != nil else {
            throw NetworkError.invalidURL(path)
        }

        var request = URLRequest(url: finalURL, timeoutInterval: timeout ?? defaultTimeout)
        request.httpMethod = method.rawValue

        var allHeaders = ["Accept": "application/json"]
        allHeaders.merge(defaultHeaders) { _, new in new }
        allHeaders.merge(headers) { _, new in new }
        for (field, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let body {
            request.httpBody = try body.encoded(using: encoder)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        return request
    }
}
