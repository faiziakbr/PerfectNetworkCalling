//
//  RetryPolicy.swift
//  PerfectNetworkCalling
//

import Foundation

/// Controls when and how often a failed request is sent again.
///
/// Retries use exponential backoff with jitter. The delay before retry *n* is
/// `baseDelay * multiplier^(n-1)`, randomly changed by up to ``jitter`` (as a fraction) in
/// either direction so many clients don't retry at the same moment, and never longer than ``maxDelay``.
/// If the server sends a `Retry-After` header, that delay is used instead (capped at
/// ``maxRetryAfter``).
///
/// ```swift
/// // Up to 3 retries for this GET only.
/// let posts: [Post] = try await client.get("/posts", retry: .default)
///
/// // Allow retries for a POST that the server handles idempotently.
/// var policy = RetryPolicy.default
/// policy.retryNonIdempotent = true
/// ```
///
/// - Important: `POST` and `PATCH` are **not** retried unless ``retryNonIdempotent`` is `true`,
///   because sending them twice could create duplicate data.
/// - Note: Cancellation is never retried, and cancelling during a backoff delay stops the
///   request immediately.
public struct RetryPolicy: Sendable, Equatable {
    /// The maximum number of retries after the first attempt. `0` turns retrying off.
    public var maxRetries: Int

    /// The delay before the first retry, in seconds.
    public var baseDelay: TimeInterval

    /// The factor the delay is multiplied by after each retry.
    public var multiplier: Double

    /// The longest delay between two attempts, in seconds.
    public var maxDelay: TimeInterval

    /// How much the delay can randomly change, as a fraction from `0` (no change) to `1`.
    public var jitter: Double

    /// HTTP status codes that trigger a retry.
    public var retryableStatusCodes: Set<Int>

    /// Whether timeouts trigger a retry.
    public var retryOnTimeout: Bool

    /// Whether connectivity errors (offline, connection lost, host unreachable) trigger a retry.
    public var retryOnConnectivityErrors: Bool

    /// Whether `POST` and `PATCH` requests may be retried. Defaults to `false`.
    public var retryNonIdempotent: Bool

    /// Whether to wait for the delay in the server's `Retry-After` header.
    public var respectsRetryAfter: Bool

    /// The longest `Retry-After` delay that is respected, in seconds. If the server asks for a
    /// longer delay, the request fails instead of waiting.
    public var maxRetryAfter: TimeInterval

    /// Creates a retry policy.
    ///
    /// - Parameters:
    ///   - maxRetries: The maximum number of retries after the first attempt.
    ///   - baseDelay: The delay before the first retry, in seconds.
    ///   - multiplier: The factor the delay is multiplied by after each retry.
    ///   - maxDelay: The longest delay between two attempts, in seconds.
    ///   - jitter: How much the delay can randomly change, from `0` to `1`.
    ///   - retryableStatusCodes: HTTP status codes that trigger a retry.
    ///   - retryOnTimeout: Whether timeouts trigger a retry.
    ///   - retryOnConnectivityErrors: Whether connectivity errors trigger a retry.
    ///   - retryNonIdempotent: Whether `POST` and `PATCH` may be retried.
    ///   - respectsRetryAfter: Whether to wait for the server's `Retry-After` delay.
    ///   - maxRetryAfter: The longest `Retry-After` delay that is respected, in seconds.
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 0.5,
        multiplier: Double = 2,
        maxDelay: TimeInterval = 10,
        jitter: Double = 0.2,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryOnTimeout: Bool = true,
        retryOnConnectivityErrors: Bool = true,
        retryNonIdempotent: Bool = false,
        respectsRetryAfter: Bool = true,
        maxRetryAfter: TimeInterval = 60
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = max(0, baseDelay)
        self.multiplier = max(1, multiplier)
        self.maxDelay = max(0, maxDelay)
        self.jitter = min(max(0, jitter), 1)
        self.retryableStatusCodes = retryableStatusCodes
        self.retryOnTimeout = retryOnTimeout
        self.retryOnConnectivityErrors = retryOnConnectivityErrors
        self.retryNonIdempotent = retryNonIdempotent
        self.respectsRetryAfter = respectsRetryAfter
        self.maxRetryAfter = max(0, maxRetryAfter)
    }

    /// Never retries.
    public static let none = RetryPolicy(maxRetries: 0)

    /// Up to 3 retries, starting at 0.5 seconds and doubling up to 10 seconds.
    public static let `default` = RetryPolicy()

    /// Up to 5 retries, starting at 0.25 seconds and doubling up to 30 seconds.
    public static let aggressive = RetryPolicy(maxRetries: 5, baseDelay: 0.25, maxDelay: 30)

    /// Decides whether a failed attempt should be retried.
    ///
    /// This only checks the type of failure. The client also checks that fewer than
    /// ``maxRetries`` retries have been made.
    ///
    /// - Parameters:
    ///   - error: The error from the failed attempt.
    ///   - method: The request's HTTP method.
    /// - Returns: `true` if the request should be sent again.
    public func shouldRetry(_ error: NetworkError, method: HTTPMethod) -> Bool {
        guard maxRetries > 0, method.isIdempotent || retryNonIdempotent else { return false }
        switch error {
        case .cancelled:
            return false
        case .timedOut:
            return retryOnTimeout
        case .noInternetConnection, .connectionLost, .cannotConnectToHost:
            return retryOnConnectivityErrors
        default:
            guard let response = error.httpResponse, retryableStatusCodes.contains(response.statusCode) else {
                return false
            }
            if respectsRetryAfter, let retryAfter = response.retryAfter, retryAfter > maxRetryAfter {
                return false
            }
            return true
        }
    }

    /// The delay before a retry.
    ///
    /// - Parameters:
    ///   - retry: The retry number, starting at `1` for the first retry.
    ///   - error: The error that caused the retry. Its `Retry-After` header is used when
    ///     ``respectsRetryAfter`` is `true`.
    /// - Returns: The delay before sending the request again.
    public func delay(forRetry retry: Int, after error: NetworkError? = nil) -> Duration {
        if respectsRetryAfter, let retryAfter = error?.httpResponse?.retryAfter {
            return .seconds(min(retryAfter, maxRetryAfter))
        }
        let exponential = baseDelay * pow(multiplier, Double(max(0, retry - 1)))
        let capped = min(exponential, maxDelay)
        let randomized = jitter > 0 ? capped * Double.random(in: (1 - jitter)...(1 + jitter)) : capped
        return .seconds(min(max(0, randomized), maxDelay))
    }
}
