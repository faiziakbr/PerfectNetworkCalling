//
//  InterceptorTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

extension MockedNetworkTests {
    @Suite("Interceptors")
    struct InterceptorTests {
        @Test func hooksRunInOrderOnEveryAttempt() async throws {
            MockURLProtocol.reset(sequence: [.status(503), .json(userJSON(1))])
            let spy = SpyInterceptor()
            let client = makeClient(retryPolicy: instantRetry(1), interceptors: [spy])
            let _: User = try await client.get("/users/1")
            #expect(spy.events.current == [
                "adapt", "willSend(1)", "didReceive(503)", "didFail(1)",
                "adapt", "willSend(2)", "didReceive(200)",
            ])
        }

        @Test func connectionFailureSkipsDidReceive() async {
            MockURLProtocol.reset { _ in .failure(.cannotFindHost) }
            let spy = SpyInterceptor()
            let client = makeClient(interceptors: [spy])
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error == .cannotConnectToHost)
            #expect(spy.events.current == ["adapt", "willSend(1)", "didFail(1)"])
        }

        @Test func adaptCanAddHeaders() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1)) }
            let spy = SpyInterceptor(addHeader: ("X-App-Version", "1.4.0"))
            let client = makeClient(interceptors: [spy])
            let _: User = try await client.get("/users/1")
            #expect(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-App-Version") == "1.4.0")
        }

        @Test func authInterceptorAddsBearerToken() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1)) }
            let client = makeClient(interceptors: [AuthInterceptor(tokenProvider: CountingTokenProvider(initial: "abc"))])
            let _: User = try await client.get("/me")
            #expect(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        }

        @Test func interceptorRetriesAreLimited() async {
            MockURLProtocol.reset { _ in .status(401) }
            struct AlwaysRetry: NetworkInterceptor {
                func retryDecision(for request: URLRequest, dueTo error: NetworkError, attempt: Int) async -> InterceptorRetryDecision { .retry }
            }
            let client = makeClient(interceptors: [AlwaysRetry()], maxInterceptorRetries: 2)
            let error = await networkError { let _: User = try await client.get("/me") }
            #expect(error?.statusCode == 401)
            #expect(MockURLProtocol.requestCount == 3)
        }

        @Test func throwingAdaptStopsRequest() async {
            MockURLProtocol.reset { _ in .json(userJSON(1)) }
            struct Failing: NetworkInterceptor {
                func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
                    throw URLError(.userAuthenticationRequired)
                }
            }
            let client = makeClient(interceptors: [Failing()])
            let error = await networkError { let _: User = try await client.get("/me") }
            #expect(error != nil)
            #expect(MockURLProtocol.requestCount == 0)
        }

        @Test func loggingInterceptorPrintsRequestAndResponse() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1)) }
            let lines = Locked<[String]>([])
            let logger = LoggingInterceptor { message in lines.withLock { $0.append(message) } }
            let auth = AuthInterceptor(tokenProvider: CountingTokenProvider(initial: "secret"))
            let client = makeClient(interceptors: [auth, logger])
            let _: User = try await client.post("/users", body: NewUser(name: "Ada"))

            let output = lines.current
            #expect(output.count == 2)
            #expect(output[0].hasPrefix("⬆️ POST https://api.test.com/users (attempt 1)"))
            #expect(output[0].contains("Authorization: ***"))
            #expect(!output[0].contains("secret"))
            #expect(output[0].contains("curl -X POST 'https://api.test.com/users'"))
            #expect(output[1].hasPrefix("✅ 200 POST https://api.test.com/users"))
            #expect(output[1].contains(#""name" : "Ada""#))
        }
    }
}

@Suite("LoggingInterceptor formatting")
struct LoggingInterceptorTests {
    private func request(body: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.test.com/users")!)
        request.httpMethod = "POST"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.map { Data($0.utf8) }
        return request
    }

    private let response = HTTPURLResponse(url: URL(string: "https://api.test.com/users")!, statusCode: 404, httpVersion: nil, headerFields: ["Set-Cookie": "session=1"])!

    @Test func bodyLevelPrintsEverything() {
        let logger = LoggingInterceptor(level: .body) { _ in }
        let text = logger.formatRequest(request(body: #"{"b":2,"a":1}"#), attempt: 1)
        #expect(text.contains("Headers:"))
        #expect(text.contains("Authorization: ***"))
        #expect(text.contains("{\n  \"a\" : 1,\n  \"b\" : 2\n}"))
        #expect(text.contains("cURL:"))
    }

    @Test func basicLevelPrintsOneLine() {
        let logger = LoggingInterceptor(level: .basic) { _ in }
        #expect(logger.formatRequest(request(body: "{}"), attempt: 2) == "⬆️ POST https://api.test.com/users (attempt 2)")
    }

    @Test func headersLevelOmitsBody() {
        let logger = LoggingInterceptor(level: .headers) { _ in }
        let text = logger.formatRequest(request(body: #"{"a":1}"#), attempt: 1)
        #expect(text.contains("Content-Type: application/json"))
        #expect(!text.contains("\"a\""))
        #expect(!text.contains("curl"))
    }

    @Test func noneLevelPrintsNothing() async {
        let lines = Locked<[String]>([])
        let logger = LoggingInterceptor(level: .none) { message in lines.withLock { $0.append(message) } }
        await logger.willSend(request(), attempt: 1)
        await logger.didReceive(response, data: Data(), for: request(), duration: .zero)
        await logger.didFail(with: .timedOut, for: request(), attempt: 1, duration: .zero)
        #expect(lines.current.isEmpty)
    }

    @Test func longBodiesAreTruncated() {
        let logger = LoggingInterceptor(level: .body, maxBodyLength: 10, includesCURL: false) { _ in }
        let text = logger.formatRequest(request(body: String(repeating: "x", count: 50)), attempt: 1)
        #expect(text.contains("xxxxxxxxxx… (truncated, 40 more characters)"))
    }

    @Test func responseRedactsHeadersAndMarksFailure() {
        let logger = LoggingInterceptor(level: .body) { _ in }
        let text = logger.formatResponse(response, data: Data(), for: request(), duration: .milliseconds(42))
        #expect(text.hasPrefix("❌ 404 POST https://api.test.com/users (42 ms)"))
        #expect(text.contains("Set-Cookie: ***"))
    }

    @Test func cURLEscapesSingleQuotes() {
        let logger = LoggingInterceptor { _ in }
        let curl = logger.cURL(for: request(body: #"{"name":"O'Brien"}"#))
        #expect(curl.contains(#"--data-raw '{"name":"O'\''Brien"}'"#))
    }

    @Test func failureLineIncludesDescription() {
        let logger = LoggingInterceptor { _ in }
        let text = logger.formatFailure(.timedOut, for: request(), attempt: 3, duration: .milliseconds(5))
        #expect(text == "⛔️ POST https://api.test.com/users failed (attempt 3, 5 ms): The request timed out.")
    }
}
