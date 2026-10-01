//
//  HTTPMethod.swift
//  PerfectNetworkCalling
//

import Foundation

/// The HTTP verb used by an ``Endpoint``.
///
/// The method controls two things besides the verb itself:
/// - Whether a request may be retried automatically (see ``isIdempotent`` and ``RetryPolicy``).
/// - Whether a request may be deduplicated (only ``get`` requests are deduplicated).
public enum HTTPMethod: String, Sendable, CaseIterable, Hashable {
    /// Reads a resource. Safe and idempotent.
    case get = "GET"
    /// Creates a resource or triggers an action. **Not** idempotent.
    case post = "POST"
    /// Replaces a resource. Idempotent.
    case put = "PUT"
    /// Partially updates a resource. **Not** idempotent.
    case patch = "PATCH"
    /// Deletes a resource. Idempotent.
    case delete = "DELETE"

    /// Whether sending the same request more than once has the same effect as sending it once.
    ///
    /// ``RetryPolicy`` only retries idempotent methods (`GET`, `PUT`, `DELETE`) unless
    /// ``RetryPolicy/retryNonIdempotent`` is `true`. This prevents a timed-out `POST` from
    /// creating the same resource twice.
    public var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: true
        case .post, .patch: false
        }
    }
}
