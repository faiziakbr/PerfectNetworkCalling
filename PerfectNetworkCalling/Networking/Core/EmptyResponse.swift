//
//  EmptyResponse.swift
//  PerfectNetworkCalling
//

import Foundation

/// A response type for requests whose body you don't need, such as `204 No Content`.
///
/// When you ask for an `EmptyResponse`, the client doesn't decode the body at all, so an
/// empty body or any body is accepted.
///
/// ```swift
/// let _: EmptyResponse = try await client.delete("/users/42")
/// ```
public struct EmptyResponse: Decodable, Sendable, Equatable {
    /// Creates an empty response.
    public init() {}

    /// Creates an empty response from a decoder without reading anything from it.
    public init(from decoder: any Decoder) throws {}
}
