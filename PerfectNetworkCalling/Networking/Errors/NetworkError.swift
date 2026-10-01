//
//  NetworkError.swift
//  PerfectNetworkCalling
//

import Foundation

/// Every error thrown by ``NetworkClient``.
///
/// Every API on the client throws `NetworkError` and nothing else, so you can always
/// `catch let error as NetworkError`. Each case has a user-readable ``errorDescription`` and a
/// ``recoverySuggestion`` that you can show directly in your UI:
///
/// ```swift
/// do {
///     let user: User = try await client.get("/me")
/// } catch let error as NetworkError {
///     showAlert(title: error.errorDescription, message: error.recoverySuggestion)
/// }
/// ```
///
/// Match a specific case when you need to react to it:
///
/// ```swift
/// catch NetworkError.unauthorized { signOut() }
/// catch NetworkError.cancelled { /* ignore */ }
/// ```
public enum NetworkError: LocalizedError, Sendable, Equatable {

    // MARK: Request preparation

    /// The URL could not be built from the base URL and path. The value is the path that failed.
    case invalidURL(String)

    /// The request body could not be encoded. The value describes the encoding error.
    case encodingFailed(String)

    // MARK: Connectivity

    /// The device is offline.
    case noInternetConnection

    /// The connection dropped while the request was in progress.
    case connectionLost

    /// The server's host name couldn't be resolved, or the server refused the connection.
    case cannotConnectToHost

    /// The TLS handshake failed or the server's certificate is invalid.
    case sslError

    /// The request took longer than its timeout.
    case timedOut

    /// The request was cancelled, by `Task.cancel()`, ``RequestToken/cancel()``,
    /// ``NetworkClient/cancelAll()`` or a newer request with the same ``Endpoint/cancellationKey``.
    case cancelled

    // MARK: HTTP status

    /// `400 Bad Request`.
    case badRequest(HTTPErrorResponse)
    /// `401 Unauthorized`.
    case unauthorized(HTTPErrorResponse)
    /// `403 Forbidden`.
    case forbidden(HTTPErrorResponse)
    /// `404 Not Found`.
    case notFound(HTTPErrorResponse)
    /// `409 Conflict`.
    case conflict(HTTPErrorResponse)
    /// `422 Unprocessable Entity`, usually a validation failure.
    case unprocessableEntity(HTTPErrorResponse)
    /// `429 Too Many Requests`. ``HTTPErrorResponse/retryAfter`` holds the server's requested delay, if any.
    case rateLimited(HTTPErrorResponse)
    /// Any other `4xx` status.
    case clientError(HTTPErrorResponse)
    /// Any `5xx` status.
    case serverError(HTTPErrorResponse)
    /// A status outside `200..<600` that isn't a success, such as an unhandled `3xx`.
    case unexpectedStatus(HTTPErrorResponse)

    // MARK: Response handling

    /// The response wasn't an HTTP response.
    case invalidResponse

    /// The response body couldn't be decoded into the requested type. The value describes
    /// which field failed and why.
    case decodingFailed(String)

    /// Any other error. The value is the underlying error's description.
    case unknown(String)

    // MARK: - Convenience

    /// The HTTP status code, for HTTP-status cases.
    public var statusCode: Int? { httpResponse?.statusCode }

    /// The server's response, for HTTP-status cases.
    public var httpResponse: HTTPErrorResponse? {
        switch self {
        case .badRequest(let response), .unauthorized(let response), .forbidden(let response),
             .notFound(let response), .conflict(let response), .unprocessableEntity(let response),
             .rateLimited(let response), .clientError(let response), .serverError(let response),
             .unexpectedStatus(let response):
            response
        default:
            nil
        }
    }

    /// Whether the error is usually temporary, so trying again later may succeed.
    ///
    /// `true` for timeouts, connectivity errors, `408`, `429` and `5xx` responses.
    /// ``RetryPolicy`` makes the actual retry decision.
    public var isTransient: Bool {
        switch self {
        case .timedOut, .noInternetConnection, .connectionLost, .cannotConnectToHost, .rateLimited, .serverError:
            true
        case .clientError(let response):
            response.statusCode == 408
        default:
            false
        }
    }

    // MARK: - LocalizedError

    /// A short, user-readable description of what went wrong.
    ///
    /// For `4xx` errors the server's own message (see ``HTTPErrorResponse/message``) is used when
    /// it sent one. `5xx` messages are not shown to users, because they are often technical.
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "The request address is invalid (\(path))."
        case .encodingFailed:
            "The request could not be prepared."
        case .noInternetConnection:
            "You appear to be offline."
        case .connectionLost:
            "The network connection was lost."
        case .cannotConnectToHost:
            "Could not connect to the server."
        case .sslError:
            "A secure connection to the server could not be established."
        case .timedOut:
            "The request timed out."
        case .cancelled:
            "The request was cancelled."
        case .badRequest(let response):
            response.message ?? "The request was invalid."
        case .unauthorized(let response):
            response.message ?? "You are not signed in, or your session has expired."
        case .forbidden(let response):
            response.message ?? "You don't have permission to do this."
        case .notFound(let response):
            response.message ?? "The requested item could not be found."
        case .conflict(let response):
            response.message ?? "The request conflicts with the current state of the item."
        case .unprocessableEntity(let response):
            response.message ?? "Some of the information you sent is invalid."
        case .rateLimited:
            "Too many requests."
        case .clientError(let response):
            response.message ?? "The request failed (error \(response.statusCode))."
        case .serverError(let response):
            "The server ran into a problem (error \(response.statusCode))."
        case .unexpectedStatus(let response):
            "The server sent an unexpected response (status \(response.statusCode))."
        case .invalidResponse:
            "The server sent an invalid response."
        case .decodingFailed:
            "The server's response could not be read."
        case .unknown(let message):
            message.isEmpty ? "Something went wrong." : message
        }
    }

    /// A user-readable suggestion for what to do next.
    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL, .encodingFailed, .invalidResponse, .decodingFailed, .unexpectedStatus, .badRequest, .clientError:
            "Please try again. If the problem continues, contact support."
        case .noInternetConnection:
            "Check your Wi-Fi or mobile data connection and try again."
        case .connectionLost, .cannotConnectToHost:
            "Check your connection and try again."
        case .sslError:
            "Make sure your device's date and time are correct, and avoid untrusted Wi-Fi networks."
        case .timedOut:
            "The server is taking too long to respond. Please try again."
        case .cancelled:
            "No action is needed."
        case .unauthorized:
            "Please sign in again."
        case .forbidden:
            "If you think you should have access, contact your administrator."
        case .notFound:
            "It may have been moved or deleted. Refresh and try again."
        case .conflict:
            "Refresh to get the latest data, then try again."
        case .unprocessableEntity:
            "Review the highlighted fields and try again."
        case .rateLimited(let response):
            if let seconds = response.retryAfter {
                "Please wait \(Int(seconds.rounded(.up))) seconds and try again."
            } else {
                "Please wait a moment and try again."
            }
        case .serverError:
            "Please try again in a few minutes."
        case .unknown:
            "Please try again."
        }
    }

    /// Technical details for logs. Not meant for users.
    public var failureReason: String? {
        switch self {
        case .encodingFailed(let detail), .decodingFailed(let detail), .unknown(let detail):
            detail
        default:
            httpResponse.map { "HTTP \($0.statusCode)" }
        }
    }

    // MARK: - Mapping

    /// Converts any error into a `NetworkError`.
    ///
    /// `NetworkError` values are returned unchanged. `CancellationError` becomes ``cancelled``,
    /// `URLError` codes become the matching connectivity case, and `DecodingError` /
    /// `EncodingError` become ``decodingFailed(_:)`` / ``encodingFailed(_:)`` with a readable
    /// description.
    ///
    /// - Parameter error: Any error.
    /// - Returns: The matching `NetworkError`.
    public static func from(_ error: any Error) -> NetworkError {
        switch error {
        case let error as NetworkError:
            return error
        case is CancellationError:
            return .cancelled
        case let error as URLError:
            return from(urlError: error)
        case let error as DecodingError:
            return .decodingFailed(describe(error))
        case let error as EncodingError:
            return .encodingFailed(String(describing: error))
        default:
            return .unknown(error.localizedDescription)
        }
    }

    /// Converts a `URLError` into a `NetworkError`.
    ///
    /// - Parameter error: The URL loading error.
    /// - Returns: The matching `NetworkError`.
    public static func from(urlError error: URLError) -> NetworkError {
        switch error.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            .noInternetConnection
        case .networkConnectionLost:
            .connectionLost
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .cannotConnectToHost
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            .sslError
        case .badURL, .unsupportedURL:
            .invalidURL(error.failingURL?.absoluteString ?? "")
        case .badServerResponse, .cannotParseResponse:
            .invalidResponse
        case .cannotDecodeContentData, .cannotDecodeRawData:
            .decodingFailed(error.localizedDescription)
        default:
            .unknown(error.localizedDescription)
        }
    }

    /// Converts an HTTP status code into a `NetworkError`.
    ///
    /// - Parameter response: The failed response.
    /// - Returns: The matching `NetworkError`, or `nil` if the status code means success (`200..<300`).
    public static func from(_ response: HTTPErrorResponse) -> NetworkError? {
        switch response.statusCode {
        case 200..<300: nil
        case 400: .badRequest(response)
        case 401: .unauthorized(response)
        case 403: .forbidden(response)
        case 404: .notFound(response)
        case 409: .conflict(response)
        case 422: .unprocessableEntity(response)
        case 429: .rateLimited(response)
        case 400..<500: .clientError(response)
        case 500..<600: .serverError(response)
        default: .unexpectedStatus(response)
        }
    }

    /// Builds a readable description of a `DecodingError`, including the path of the failing field.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context, appending key: (any CodingKey)? = nil) -> String {
            let keys = context.codingPath + (key.map { [$0] } ?? [])
            let joined = keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            return joined.isEmpty ? "<root>" : joined.replacingOccurrences(of: ".[", with: "[")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(path(context, appending: key))."
        case .typeMismatch(let type, let context):
            return "Type mismatch at \(path(context)): expected \(type). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value at \(path(context)): expected \(type)."
        case .dataCorrupted(let context):
            return "Invalid data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}
