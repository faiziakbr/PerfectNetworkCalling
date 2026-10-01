//
//  HTTPErrorResponse.swift
//  PerfectNetworkCalling
//

import Foundation

/// The details of an HTTP response whose status code means failure.
///
/// HTTP-status cases of ``NetworkError`` carry this value, so you can read the status code,
/// headers and raw body, or decode the body into your own error model:
///
/// ```swift
/// catch let NetworkError.unprocessableEntity(response) {
///     let errors = try? response.decode(ValidationErrors.self)
/// }
/// ```
public struct HTTPErrorResponse: Sendable, Equatable {
    /// The HTTP status code.
    public let statusCode: Int

    /// The response headers. Field names keep the case the server sent.
    public let headers: [String: String]

    /// The raw response body.
    public let data: Data

    /// A message read from the response body, if the server sent one.
    ///
    /// The client looks for the JSON fields `message`, `error_description`, `detail`, `error`
    /// and `title`, including inside a nested `error` object. If the body isn't JSON, short
    /// plain text is used as is.
    public let message: String?

    /// Creates an error response.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - headers: The response headers.
    ///   - data: The raw response body.
    public init(statusCode: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
        self.message = Self.extractMessage(from: data)
    }

    /// Creates an error response from an `HTTPURLResponse` and its body.
    ///
    /// - Parameters:
    ///   - response: The HTTP response.
    ///   - data: The response body.
    public init(response: HTTPURLResponse, data: Data) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        self.init(statusCode: response.statusCode, headers: headers, data: data)
    }

    /// Returns the value of a header, matching the field name without regard to case.
    ///
    /// - Parameter field: The header field name.
    /// - Returns: The header value, or `nil` if the header is missing.
    public func header(_ field: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }

    /// The delay the server asked for in its `Retry-After` header, in seconds.
    ///
    /// Supports both forms of the header: a number of seconds, and an HTTP date.
    public var retryAfter: TimeInterval? {
        guard let value = header("Retry-After")?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    /// Decodes the response body into your own error type.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - decoder: The decoder to use.
    /// - Returns: The decoded value.
    /// - Throws: The decoder's error if the body doesn't match `type`.
    public func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: data)
    }

    // MARK: - Message extraction

    private static let messageKeys = ["message", "error_description", "detail", "error", "title"]

    static func extractMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return message(in: json)
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 200, !text.hasPrefix("<") else {
            return nil
        }
        return text
    }

    private static func message(in json: Any) -> String? {
        if let dictionary = json as? [String: Any] {
            for key in messageKeys {
                if let string = dictionary[key] as? String, !string.isEmpty { return string }
                if let nested = dictionary[key], let string = message(in: nested) { return string }
            }
            if let errors = dictionary["errors"] { return message(in: errors) }
        } else if let array = json as? [Any], let first = array.first {
            return (first as? String) ?? message(in: first)
        }
        return nil
    }
}
