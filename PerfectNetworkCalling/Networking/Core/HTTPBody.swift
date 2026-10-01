//
//  HTTPBody.swift
//  PerfectNetworkCalling
//

import Foundation

/// The body sent with a request.
///
/// ```swift
/// let json: HTTPBody = .json(NewUser(name: "Ada"))
/// let form: HTTPBody = .formURLEncoded(["grant_type": "password"])
/// let raw:  HTTPBody = .data(imageData, contentType: "image/png")
/// ```
public enum HTTPBody: Sendable {
    /// A value encoded as JSON with the client's `JSONEncoder`.
    ///
    /// Sets `Content-Type: application/json` unless the request already has a `Content-Type` header.
    case json(any Encodable & Sendable)

    /// Raw bytes with an explicit content type.
    case data(Data, contentType: String)

    /// Key-value pairs encoded as `application/x-www-form-urlencoded`. Keys are sorted so the
    /// body is always the same for the same input.
    case formURLEncoded([String: String])

    /// The value of the `Content-Type` header this body needs.
    public var contentType: String {
        switch self {
        case .json: "application/json"
        case .data(_, let contentType): contentType
        case .formURLEncoded: "application/x-www-form-urlencoded; charset=utf-8"
        }
    }

    /// Encodes the body into bytes.
    ///
    /// - Parameter encoder: The encoder used for ``json(_:)`` bodies.
    /// - Returns: The encoded body.
    /// - Throws: ``NetworkError/encodingFailed(_:)`` if a JSON value cannot be encoded.
    public func encoded(using encoder: JSONEncoder) throws -> Data {
        switch self {
        case .json(let value):
            do {
                return try encoder.encode(value)
            } catch {
                throw NetworkError.encodingFailed(String(describing: error))
            }
        case .data(let data, _):
            return data
        case .formURLEncoded(let fields):
            let encoded = fields
                .sorted { $0.key < $1.key }
                .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
                .joined(separator: "&")
            return Data(encoded.utf8)
        }
    }

    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._*")
        return set
    }()

    private static func formEncode(_ string: String) -> String {
        (string.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? string)
            .replacingOccurrences(of: "%20", with: "+")
    }
}
