//
//  NetworkErrorTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

@Suite("NetworkError")
struct NetworkErrorTests {

    @Test(arguments: [
        (400, "badRequest"), (401, "unauthorized"), (403, "forbidden"), (404, "notFound"),
        (409, "conflict"), (422, "unprocessableEntity"), (429, "rateLimited"), (418, "clientError"),
        (500, "serverError"), (503, "serverError"), (304, "unexpectedStatus"),
    ])
    func statusCodeMapping(status: Int, expectedCase: String) throws {
        let error = try #require(NetworkError.from(HTTPErrorResponse(statusCode: status)))
        #expect(String(describing: error).hasPrefix(expectedCase))
        #expect(error.statusCode == status)
    }

    @Test(arguments: [200, 201, 204, 299])
    func successStatusIsNotAnError(status: Int) {
        #expect(NetworkError.from(HTTPErrorResponse(statusCode: status)) == nil)
    }

    @Test(arguments: [
        (URLError.Code.cancelled, NetworkError.cancelled),
        (.timedOut, .timedOut),
        (.notConnectedToInternet, .noInternetConnection),
        (.networkConnectionLost, .connectionLost),
        (.cannotFindHost, .cannotConnectToHost),
        (.cannotConnectToHost, .cannotConnectToHost),
        (.serverCertificateUntrusted, .sslError),
        (.badServerResponse, .invalidResponse),
    ])
    func urlErrorMapping(code: URLError.Code, expected: NetworkError) {
        #expect(NetworkError.from(URLError(code)) == expected)
    }

    @Test func cancellationErrorMapsToCancelled() {
        #expect(NetworkError.from(CancellationError()) == .cancelled)
    }

    @Test func networkErrorIsReturnedUnchanged() {
        #expect(NetworkError.from(NetworkError.timedOut) == .timedOut)
    }

    @Test func decodingErrorDescribesFailingPath() {
        struct Wrapper: Decodable { let user: User }
        do {
            _ = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"user":{"id":1}}"#.utf8))
            Issue.record("Decoding should fail")
        } catch {
            guard case .decodingFailed(let detail) = NetworkError.from(error) else {
                Issue.record("Expected decodingFailed")
                return
            }
            #expect(detail.contains("Missing key 'name'"))
            #expect(detail.contains("user.name"))
        }
    }

    @Test(arguments: [
        #"{"message":"Email is already taken"}"#,
        #"{"error":{"message":"Email is already taken"}}"#,
        #"{"errors":[{"detail":"Email is already taken"}]}"#,
        #"{"error_description":"Email is already taken"}"#,
        "Email is already taken",
    ])
    func serverMessageIsShownForClientErrors(body: String) {
        let error = NetworkError.from(HTTPErrorResponse(statusCode: 409, data: Data(body.utf8)))
        #expect(error?.errorDescription == "Email is already taken")
    }

    @Test func serverMessageIsHiddenForServerErrors() {
        let error = NetworkError.from(HTTPErrorResponse(statusCode: 500, data: Data(#"{"message":"NullPointerException"}"#.utf8)))
        #expect(error?.errorDescription?.contains("NullPointerException") == false)
        #expect(error?.errorDescription?.contains("500") == true)
    }

    @Test func htmlBodyIsNotUsedAsMessage() {
        let error = NetworkError.from(HTTPErrorResponse(statusCode: 404, data: Data("<html>Not Found</html>".utf8)))
        #expect(error?.errorDescription == "The requested item could not be found.")
    }

    @Test func retryAfterIsParsed() {
        let seconds = HTTPErrorResponse(statusCode: 429, headers: ["retry-after": "12"])
        #expect(seconds.retryAfter == 12)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        let date = HTTPErrorResponse(statusCode: 429, headers: ["Retry-After": formatter.string(from: Date().addingTimeInterval(30))])
        #expect((25...31).contains(date.retryAfter ?? 0))

        let error = NetworkError.rateLimited(seconds)
        #expect(error.recoverySuggestion == "Please wait 12 seconds and try again.")
    }

    @Test func errorBodyCanBeDecodedIntoCustomType() throws {
        struct APIError: Decodable { let code: String }
        let response = HTTPErrorResponse(statusCode: 422, data: Data(#"{"code":"INVALID_EMAIL"}"#.utf8))
        #expect(try response.decode(APIError.self).code == "INVALID_EMAIL")
    }

    @Test func everyCaseHasReadableMessages() {
        let response = HTTPErrorResponse(statusCode: 400)
        let all: [NetworkError] = [
            .invalidURL("/x"), .encodingFailed("x"), .noInternetConnection, .connectionLost,
            .cannotConnectToHost, .sslError, .timedOut, .cancelled, .badRequest(response),
            .unauthorized(response), .forbidden(response), .notFound(response), .conflict(response),
            .unprocessableEntity(response), .rateLimited(response), .clientError(response),
            .serverError(response), .unexpectedStatus(response), .invalidResponse,
            .decodingFailed("x"), .unknown("x"),
        ]
        for error in all {
            #expect(error.errorDescription?.isEmpty == false, "\(error)")
            #expect(error.recoverySuggestion?.isEmpty == false, "\(error)")
            #expect(error.localizedDescription == error.errorDescription, "\(error)")
        }
    }

    @Test(arguments: [
        (NetworkError.timedOut, true), (.noInternetConnection, true), (.serverError(HTTPErrorResponse(statusCode: 503)), true),
        (.clientError(HTTPErrorResponse(statusCode: 408)), true), (.notFound(HTTPErrorResponse(statusCode: 404)), false),
        (.cancelled, false), (.decodingFailed("x"), false),
    ])
    func transientErrors(error: NetworkError, expected: Bool) {
        #expect(error.isTransient == expected)
    }
}
