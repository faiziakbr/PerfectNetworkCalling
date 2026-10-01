//
//  NetworkInterceptor.swift
//  PerfectNetworkCalling
//

import Foundation

/// What an interceptor wants the client to do after a failed attempt.
public enum InterceptorRetryDecision: Sendable, Equatable {
    /// Don't retry because of this interceptor. The ``RetryPolicy`` still decides on its own.
    case doNotRetry
    /// Send the request again right away. ``NetworkInterceptor/adapt(_:for:)`` runs again first.
    case retry
    /// Send the request again after a delay.
    case retryAfter(Duration)
}

/// A hook into every request the client sends.
///
/// Use interceptors to change requests (for example, to add an auth token), to observe
/// requests and responses (for example, for logging or analytics), or to retry after fixing
/// the cause of a failure (for example, refreshing an expired token).
///
/// Every method has a default implementation that does nothing, so you only implement
/// the hooks you need. For each attempt the client calls, in order:
///
/// 1. ``adapt(_:for:)`` on every interceptor, in the order they are listed in ``NetworkConfiguration/interceptors``.
/// 2. ``willSend(_:attempt:)``.
/// 3. ``didReceive(_:data:for:duration:)`` when any HTTP response arrives, including error statuses.
/// 4. ``didFail(with:for:attempt:duration:)`` when the attempt fails, followed by
///    ``retryDecision(for:dueTo:attempt:)``.
///
/// All hooks run again for every retry attempt.
///
/// ```swift
/// struct AppVersionInterceptor: NetworkInterceptor {
///     func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
///         var request = request
///         request.setValue("1.4.0", forHTTPHeaderField: "X-App-Version")
///         return request
///     }
/// }
/// ```
///
/// - Important: Interceptors must be `Sendable`, because the client calls them from many
///   requests at once. Keep any mutable state inside an `actor`.
public protocol NetworkInterceptor: Sendable {
    /// Changes a request before it is sent.
    ///
    /// - Parameters:
    ///   - request: The request built so far.
    ///   - endpoint: The endpoint the request was built from.
    /// - Returns: The request to send.
    /// - Throws: Any error. It stops the request and is thrown to the caller as a ``NetworkError``.
    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest

    /// Called just before an attempt is sent.
    ///
    /// - Parameters:
    ///   - request: The final request.
    ///   - attempt: The attempt number, starting at `1`.
    func willSend(_ request: URLRequest, attempt: Int) async

    /// Called when an HTTP response arrives, whatever its status code.
    ///
    /// - Parameters:
    ///   - response: The HTTP response.
    ///   - data: The response body.
    ///   - request: The request that was sent.
    ///   - duration: How long the attempt took.
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) async

    /// Called when an attempt fails.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - request: The request that was sent.
    ///   - attempt: The attempt number, starting at `1`.
    ///   - duration: How long the attempt took.
    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async

    /// Decides whether to send a failed request again, for example after refreshing a token.
    ///
    /// Retries requested here don't count against ``RetryPolicy/maxRetries``. They are limited by
    /// ``NetworkConfiguration/maxInterceptorRetries`` instead. Cancelled requests are never retried.
    ///
    /// - Parameters:
    ///   - request: The request that failed.
    ///   - error: The error.
    ///   - attempt: The attempt number, starting at `1`.
    /// - Returns: Whether and when to retry.
    func retryDecision(for request: URLRequest, dueTo error: NetworkError, attempt: Int) async -> InterceptorRetryDecision
}

public extension NetworkInterceptor {
    /// Returns the request unchanged.
    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest { request }
    /// Does nothing.
    func willSend(_ request: URLRequest, attempt: Int) async {}
    /// Does nothing.
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) async {}
    /// Does nothing.
    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async {}
    /// Returns ``InterceptorRetryDecision/doNotRetry``.
    func retryDecision(for request: URLRequest, dueTo error: NetworkError, attempt: Int) async -> InterceptorRetryDecision {
        .doNotRetry
    }
}
