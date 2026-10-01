//
//  RequestToken.swift
//  PerfectNetworkCalling
//

import Foundation

/// A handle to a request started with ``NetworkClient/send(_:as:callbackQueue:completion:)``.
///
/// Keep the token to cancel the request later:
///
/// ```swift
/// private var loadToken: RequestToken?
///
/// func load() {
///     loadToken = client.send(.get("/feed"), as: Feed.self) { result in ... }
/// }
///
/// deinit { loadToken?.cancel() }
/// ```
///
/// Dropping the token does **not** cancel the request.
public struct RequestToken: Sendable, Hashable {
    /// A unique identifier for the request.
    public let id: UUID

    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.id = UUID()
        self.task = task
    }

    /// Cancels the request. The completion handler receives ``NetworkError/cancelled``.
    /// Cancelling a finished request does nothing.
    public func cancel() {
        task.cancel()
    }

    /// Whether ``cancel()`` has been called.
    public var isCancelled: Bool {
        task.isCancelled
    }

    /// Two tokens are equal when they refer to the same request.
    public static func == (lhs: RequestToken, rhs: RequestToken) -> Bool { lhs.id == rhs.id }

    /// Hashes the token's ``id``.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
