//
//  NetworkConfiguration.swift
//  PerfectNetworkCalling
//

import Foundation

/// Settings shared by every request a ``NetworkClient`` sends.
///
/// ```swift
/// let configuration = NetworkConfiguration(
///     baseURL: URL(string: "https://api.example.com/v1")!,
///     defaultHeaders: ["X-Platform": "iOS"],
///     timeout: 20,
///     retryPolicy: .default,
///     interceptors: [AuthInterceptor(tokenProvider: session), LoggingInterceptor()]
/// )
/// let client = NetworkClient(configuration: configuration)
/// ```
public struct NetworkConfiguration: Sendable {
    /// The URL that every ``Endpoint/path`` is appended to.
    public var baseURL: URL

    /// Headers added to every request. ``Endpoint/headers`` override them.
    /// `Accept: application/json` is always added unless you override it.
    public var defaultHeaders: [String: String]

    /// The default maximum time for one attempt, in seconds. ``Endpoint/timeout`` overrides it.
    public var timeout: TimeInterval

    /// The longest time the session spends on any single transfer, in seconds.
    /// Only used when the client creates its own `URLSession`.
    public var resourceTimeout: TimeInterval

    /// The default retry policy. ``Endpoint/retryPolicy`` overrides it.
    public var retryPolicy: RetryPolicy

    /// The interceptors every request goes through, in order.
    public var interceptors: [any NetworkInterceptor]

    /// The most retries a request can make because an interceptor asked for them, such as
    /// after a token refresh. These don't count against ``RetryPolicy/maxRetries``.
    public var maxInterceptorRetries: Int

    /// The encoder for JSON request bodies.
    public var encoder: JSONEncoder

    /// The decoder for JSON responses.
    public var decoder: JSONDecoder

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - baseURL: The URL every endpoint path is appended to.
    ///   - defaultHeaders: Headers added to every request.
    ///   - timeout: The default maximum time for one attempt, in seconds. Defaults to 30.
    ///   - resourceTimeout: The longest time for any single transfer, in seconds. Defaults to 300.
    ///   - retryPolicy: The default retry policy. Defaults to ``RetryPolicy/default``.
    ///   - interceptors: The interceptors every request goes through. Defaults to a
    ///     ``LoggingInterceptor`` in `DEBUG` builds, and none in release builds.
    ///   - maxInterceptorRetries: The most retries interceptors can ask for. Defaults to 1.
    ///   - encoder: The encoder for JSON request bodies.
    ///   - decoder: The decoder for JSON responses.
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 300,
        retryPolicy: RetryPolicy = .default,
        interceptors: [any NetworkInterceptor] = NetworkConfiguration.defaultInterceptors,
        maxInterceptorRetries: Int = 1,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.resourceTimeout = resourceTimeout
        self.retryPolicy = retryPolicy
        self.interceptors = interceptors
        self.maxInterceptorRetries = max(0, maxInterceptorRetries)
        self.encoder = encoder
        self.decoder = decoder
    }

    /// A ``LoggingInterceptor`` in `DEBUG` builds, and no interceptors in release builds.
    public static var defaultInterceptors: [any NetworkInterceptor] {
        #if DEBUG
        [LoggingInterceptor()]
        #else
        []
        #endif
    }
}
