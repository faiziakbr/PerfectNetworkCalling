//
//  AuthInterceptor.swift
//  PerfectNetworkCalling
//

import Foundation

/// Supplies and refreshes the access token used by ``AuthInterceptor``.
///
/// ```swift
/// actor SessionStore: AuthTokenProvider {
///     private var accessToken: String?
///     func token() async throws -> String? { accessToken }
///     func refreshToken() async throws -> String {
///         let fresh = try await authAPI.refresh()
///         accessToken = fresh
///         return fresh
///     }
/// }
/// ```
public protocol AuthTokenProvider: Sendable {
    /// Returns the current access token, or `nil` if the user isn't signed in.
    ///
    /// - Returns: The token.
    func token() async throws -> String?

    /// Gets a new access token, for example by using a refresh token.
    ///
    /// ``AuthInterceptor`` calls this at most once at a time, however many requests fail with
    /// `401` together.
    ///
    /// - Returns: The new token.
    /// - Throws: Any error if refreshing fails. Every waiting request then fails with
    ///   ``NetworkError/unauthorized(_:)``.
    func refreshToken() async throws -> String
}

/// Adds an access token to every request and refreshes it once when requests fail with `401`.
///
/// ```swift
/// let client = NetworkClient(configuration: .init(
///     baseURL: URL(string: "https://api.example.com")!,
///     interceptors: [AuthInterceptor(tokenProvider: sessionStore), LoggingInterceptor()]
/// ))
/// ```
///
/// When several requests get `401` at the same time, only one refresh runs. The other
/// requests wait for that refresh and then retry with the new token (see ``TokenRefresher``).
/// A request that was sent with an old token and fails *after* the refresh has finished retries
/// with the new token without refreshing again.
public struct AuthInterceptor: NetworkInterceptor {
    /// The header the token is written to. Defaults to `Authorization`.
    public let headerField: String

    /// The prefix written before the token, such as `Bearer`. An empty string writes the token alone.
    public let scheme: String

    private let refresher: TokenRefresher

    /// Creates an auth interceptor.
    ///
    /// - Parameters:
    ///   - tokenProvider: Supplies and refreshes the token.
    ///   - headerField: The header the token is written to.
    ///   - scheme: The prefix written before the token.
    public init(tokenProvider: any AuthTokenProvider, headerField: String = "Authorization", scheme: String = "Bearer") {
        self.refresher = TokenRefresher(provider: tokenProvider)
        self.headerField = headerField
        self.scheme = scheme
    }

    /// Adds the current token to the request. Waits if a refresh is in progress.
    public func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
        guard let token = try await refresher.validToken() else { return request }
        var request = request
        request.setValue(scheme.isEmpty ? token : "\(scheme) \(token)", forHTTPHeaderField: headerField)
        return request
    }

    /// Refreshes the token and retries when the request failed with `401`.
    public func retryDecision(for request: URLRequest, dueTo error: NetworkError, attempt: Int) async -> InterceptorRetryDecision {
        guard case .unauthorized = error else { return .doNotRetry }
        do {
            _ = try await refresher.refresh(replacing: token(in: request))
            return .retry
        } catch {
            return .doNotRetry
        }
    }

    private func token(in request: URLRequest) -> String? {
        guard let value = request.value(forHTTPHeaderField: headerField) else { return nil }
        let prefix = scheme.isEmpty ? "" : "\(scheme) "
        return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }
}

/// Makes sure only one token refresh runs at a time.
///
/// This actor handles *actor reentrancy*: while it awaits the refresh, other callers can enter
/// it. To keep its state consistent:
/// - The in-flight refresh is stored as a `Task` **before** the first `await`. Callers that
///   arrive while it runs await the same task instead of starting another refresh.
/// - The task is cleared only after it finishes, and only if it is still the current task.
/// - A caller whose request used an older token than the current one gets the current token
///   without refreshing, because someone else already refreshed.
public actor TokenRefresher {
    private let provider: any AuthTokenProvider
    private var currentToken: String?
    private var refreshTask: Task<String, any Error>?

    /// The number of refreshes that have started. Useful in tests.
    public private(set) var refreshCount = 0

    /// Creates a refresher.
    ///
    /// - Parameter provider: The token provider.
    public init(provider: any AuthTokenProvider) {
        self.provider = provider
    }

    /// Returns the token to send. Waits for an in-flight refresh first.
    ///
    /// - Returns: The token, or `nil` if the user isn't signed in.
    /// - Throws: The provider's error.
    public func validToken() async throws -> String? {
        if let refreshTask {
            return try await refreshTask.value
        }
        if let currentToken {
            return currentToken
        }
        let token = try await provider.token()
        // A refresh may have finished while we were waiting. Its token is newer, so keep it.
        if currentToken == nil {
            currentToken = token
        }
        return currentToken
    }

    /// Refreshes the token, or joins a refresh that is already running.
    ///
    /// - Parameter failedToken: The token the failed request was sent with.
    /// - Returns: The new token.
    /// - Throws: The provider's error if refreshing fails.
    @discardableResult
    public func refresh(replacing failedToken: String?) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        if let currentToken, currentToken != failedToken {
            return currentToken
        }

        let provider = provider
        let task = Task { try await provider.refreshToken() }
        refreshTask = task
        refreshCount += 1

        do {
            let token = try await task.value
            currentToken = token
            clear(task)
            return token
        } catch {
            currentToken = nil
            clear(task)
            throw error
        }
    }

    private func clear(_ task: Task<String, any Error>) {
        if refreshTask == task {
            refreshTask = nil
        }
    }
}
