//
//  LoggingInterceptor.swift
//  PerfectNetworkCalling
//

import Foundation
import os

/// Prints requests and responses to the Xcode console.
///
/// It's enabled by default in `DEBUG` builds (see ``NetworkConfiguration/interceptors``).
/// At the ``Level/body`` level, a request looks like this:
///
/// ```text
/// ⬆️ POST https://api.example.com/users (attempt 1)
/// Headers:
///   Authorization: ***
///   Content-Type: application/json
/// Body:
/// {
///   "name" : "Ada"
/// }
/// cURL:
/// curl -X POST 'https://api.example.com/users' -H 'Authorization: ***' -H 'Content-Type: application/json' --data-raw '{"name":"Ada"}'
///
/// ✅ 201 POST https://api.example.com/users (84 ms)
/// Body:
/// {
///   "id" : 7,
///   "name" : "Ada"
/// }
/// ```
///
/// Messages go to the unified logging system (`os.Logger`), so they show in the Xcode console and
/// in Console.app, where you can filter by ``subsystem`` and ``category``.
///
/// - Important: Sensitive headers are replaced with `***` (see ``redactedHeaders``). Bodies are
///   printed as they are, so avoid the ``Level/body`` level in release builds.
public struct LoggingInterceptor: NetworkInterceptor {

    /// How much detail is printed.
    public enum Level: Int, Sendable, Comparable, CaseIterable {
        /// Nothing is printed.
        case none
        /// One line per request and one per response or failure.
        case basic
        /// ``basic`` plus headers.
        case headers
        /// ``headers`` plus bodies and a cURL command.
        case body

        /// Orders levels from least to most detail.
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The amount of detail printed.
    public var level: Level

    /// The longest body that is printed in full, in characters. Longer bodies are truncated.
    public var maxBodyLength: Int

    /// Header names, matched without regard to case, whose values are printed as `***`.
    public var redactedHeaders: Set<String>

    /// Whether a ready-to-paste cURL command is printed for each request at the ``Level/body`` level.
    public var includesCURL: Bool

    /// The logging subsystem.
    public let subsystem: String

    /// The logging category.
    public let category: String

    private let output: @Sendable (String) -> Void

    /// Creates a logging interceptor that writes to `os.Logger`.
    ///
    /// - Parameters:
    ///   - level: The amount of detail printed.
    ///   - maxBodyLength: The longest body printed in full, in characters.
    ///   - redactedHeaders: Header names whose values are printed as `***`.
    ///   - includesCURL: Whether a cURL command is printed at the ``Level/body`` level.
    ///   - subsystem: The logging subsystem.
    ///   - category: The logging category.
    public init(
        level: Level = .body,
        maxBodyLength: Int = 4_000,
        redactedHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie", "Proxy-Authorization"],
        includesCURL: Bool = true,
        subsystem: String = "PerfectNetworkCalling",
        category: String = "Network"
    ) {
        let logger = Logger(subsystem: subsystem, category: category)
        self.init(level: level, maxBodyLength: maxBodyLength, redactedHeaders: redactedHeaders,
                  includesCURL: includesCURL, subsystem: subsystem, category: category) { message in
            logger.debug("\(message, privacy: .public)")
        }
    }

    /// Creates a logging interceptor that sends each message to your own closure, for example
    /// `print` or a file logger.
    ///
    /// - Parameters:
    ///   - level: The amount of detail printed.
    ///   - maxBodyLength: The longest body printed in full, in characters.
    ///   - redactedHeaders: Header names whose values are printed as `***`.
    ///   - includesCURL: Whether a cURL command is printed at the ``Level/body`` level.
    ///   - subsystem: The logging subsystem, kept for reference.
    ///   - category: The logging category, kept for reference.
    ///   - output: Receives each formatted message.
    public init(
        level: Level = .body,
        maxBodyLength: Int = 4_000,
        redactedHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie", "Proxy-Authorization"],
        includesCURL: Bool = true,
        subsystem: String = "PerfectNetworkCalling",
        category: String = "Network",
        output: @escaping @Sendable (String) -> Void
    ) {
        self.level = level
        self.maxBodyLength = max(0, maxBodyLength)
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.includesCURL = includesCURL
        self.subsystem = subsystem
        self.category = category
        self.output = output
    }

    // MARK: - NetworkInterceptor

    /// Prints the request, formatted by ``formatRequest(_:attempt:)``.
    public func willSend(_ request: URLRequest, attempt: Int) async {
        guard level > .none else { return }
        output(formatRequest(request, attempt: attempt))
    }

    /// Prints the response, formatted by ``formatResponse(_:data:for:duration:)``.
    public func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) async {
        guard level > .none else { return }
        output(formatResponse(response, data: data, for: request, duration: duration))
    }

    /// Prints the failure, formatted by ``formatFailure(_:for:attempt:duration:)``.
    public func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async {
        guard level > .none else { return }
        output(formatFailure(error, for: request, attempt: attempt, duration: duration))
    }

    // MARK: - Formatting

    /// Formats a request the way it is printed.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - attempt: The attempt number.
    /// - Returns: The formatted message.
    public func formatRequest(_ request: URLRequest, attempt: Int) -> String {
        var lines = ["⬆️ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<no url>") (attempt \(attempt))"]
        if level >= .headers {
            lines += formatHeaders(request.allHTTPHeaderFields ?? [:])
        }
        if level >= .body {
            if let body = request.httpBody, !body.isEmpty {
                lines += ["Body:", formatBody(body)]
            }
            if includesCURL {
                lines += ["cURL:", cURL(for: request)]
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Formats a response the way it is printed.
    ///
    /// - Parameters:
    ///   - response: The HTTP response.
    ///   - data: The response body.
    ///   - request: The request that was sent.
    ///   - duration: How long the attempt took.
    /// - Returns: The formatted message.
    public func formatResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) -> String {
        let icon = (200..<300).contains(response.statusCode) ? "✅" : "❌"
        let url = response.url?.absoluteString ?? request.url?.absoluteString ?? "<no url>"
        var lines = ["\(icon) \(response.statusCode) \(request.httpMethod ?? "GET") \(url) (\(Self.milliseconds(duration)) ms)"]
        if level >= .headers {
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            lines += formatHeaders(headers)
        }
        if level >= .body, !data.isEmpty {
            lines += ["Body:", formatBody(data)]
        }
        return lines.joined(separator: "\n")
    }

    /// Formats a failure the way it is printed.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - request: The request that was sent.
    ///   - attempt: The attempt number.
    ///   - duration: How long the attempt took.
    /// - Returns: The formatted message.
    public func formatFailure(_ error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) -> String {
        let description = error.errorDescription ?? "Unknown error"
        let reason = error.failureReason.map { " [\($0)]" } ?? ""
        return "⛔️ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<no url>") failed (attempt \(attempt), \(Self.milliseconds(duration)) ms): \(description)\(reason)"
    }

    /// Builds a cURL command that repeats the request. Redacted headers stay redacted.
    ///
    /// - Parameter request: The request.
    /// - Returns: The command.
    public func cURL(for request: URLRequest) -> String {
        var parts = ["curl -X \(request.httpMethod ?? "GET") \(Self.shellQuoted(request.url?.absoluteString ?? ""))"]
        for (field, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("-H \(Self.shellQuoted("\(field): \(redacted(field, value))"))")
        }
        if let body = request.httpBody, !body.isEmpty {
            let text = String(data: body, encoding: .utf8) ?? "<\(body.count) bytes of binary data>"
            parts.append("--data-raw \(Self.shellQuoted(text))")
        }
        return parts.joined(separator: " ")
    }

    private func formatHeaders(_ headers: [String: String]) -> [String] {
        guard !headers.isEmpty else { return [] }
        return ["Headers:"] + headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "  \($0.key): \(redacted($0.key, $0.value))" }
    }

    private func redacted(_ field: String, _ value: String) -> String {
        redactedHeaders.contains(field.lowercased()) ? "***" : value
    }

    private func formatBody(_ data: Data) -> String {
        let text: String
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
           let string = String(data: pretty, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            return "<\(data.count) bytes of binary data>"
        }
        guard text.count > maxBodyLength else { return text }
        return "\(text.prefix(maxBodyLength))… (truncated, \(text.count - maxBodyLength) more characters)"
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }

    private static func shellQuoted(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
