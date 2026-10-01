//
//  RetryPolicyTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

@Suite("RetryPolicy rules")
struct RetryPolicyRuleTests {
    private let serverError = NetworkError.serverError(HTTPErrorResponse(statusCode: 503))

    @Test func retriesTransientErrorsForIdempotentMethods() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(serverError, method: .get))
        #expect(policy.shouldRetry(.timedOut, method: .put))
        #expect(policy.shouldRetry(.connectionLost, method: .delete))
    }

    @Test func doesNotRetryNonIdempotentMethodsByDefault() {
        #expect(!RetryPolicy.default.shouldRetry(serverError, method: .post))
        #expect(!RetryPolicy.default.shouldRetry(.timedOut, method: .patch))
        var policy = RetryPolicy.default
        policy.retryNonIdempotent = true
        #expect(policy.shouldRetry(serverError, method: .post))
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422])
    func doesNotRetryClientErrors(status: Int) throws {
        let error = try #require(NetworkError.from(HTTPErrorResponse(statusCode: status)))
        #expect(!RetryPolicy.default.shouldRetry(error, method: .get))
    }

    @Test func neverRetriesCancellation() {
        #expect(!RetryPolicy.aggressive.shouldRetry(.cancelled, method: .get))
    }

    @Test func noneNeverRetries() {
        #expect(!RetryPolicy.none.shouldRetry(serverError, method: .get))
    }

    @Test func backoffGrowsAndIsCapped() {
        let policy = RetryPolicy(baseDelay: 1, multiplier: 2, maxDelay: 5, jitter: 0)
        #expect(policy.delay(forRetry: 1) == .seconds(1))
        #expect(policy.delay(forRetry: 2) == .seconds(2))
        #expect(policy.delay(forRetry: 3) == .seconds(4))
        #expect(policy.delay(forRetry: 4) == .seconds(5))
    }

    @Test func jitterStaysWithinBounds() {
        let policy = RetryPolicy(baseDelay: 1, multiplier: 2, maxDelay: 10, jitter: 0.5)
        for _ in 0..<200 {
            let delay = policy.delay(forRetry: 2)
            #expect(delay >= .seconds(1) && delay <= .seconds(3))
        }
    }

    @Test func retryAfterHeaderWins() {
        let policy = RetryPolicy(baseDelay: 1, jitter: 0)
        let error = NetworkError.rateLimited(HTTPErrorResponse(statusCode: 429, headers: ["Retry-After": "7"]))
        #expect(policy.delay(forRetry: 1, after: error) == .seconds(7))
    }

    @Test func retryAfterLongerThanMaximumIsNotRetried() {
        let policy = RetryPolicy(maxRetryAfter: 5)
        let error = NetworkError.rateLimited(HTTPErrorResponse(statusCode: 429, headers: ["Retry-After": "120"]))
        #expect(!policy.shouldRetry(error, method: .get))
    }
}

extension MockedNetworkTests {
    @Suite("Retrying requests")
    struct RetryTests {
        @Test func succeedsAfterTwoRetries() async throws {
            MockURLProtocol.reset(sequence: [.status(503), .status(503), .json(userJSON(1))])
            let client = makeClient(retryPolicy: instantRetry(3))
            let user: User = try await client.get("/users/1")
            #expect(user.id == 1)
            #expect(MockURLProtocol.requestCount == 3)
        }

        @Test func stopsAtMaxRetries() async {
            MockURLProtocol.reset(sequence: [.status(500)])
            let client = makeClient(retryPolicy: instantRetry(2))
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error?.statusCode == 500)
            #expect(MockURLProtocol.requestCount == 3)
        }

        @Test func postIsNotRetriedByDefault() async {
            MockURLProtocol.reset(sequence: [.status(503), .json(userJSON(1))])
            let client = makeClient(retryPolicy: instantRetry(3))
            let error = await networkError { let _: User = try await client.post("/users", body: NewUser(name: "Ada")) }
            #expect(error?.statusCode == 503)
            #expect(MockURLProtocol.requestCount == 1)
        }

        @Test func postIsRetriedWhenOptedIn() async throws {
            MockURLProtocol.reset(sequence: [.status(503), .json(userJSON(1))])
            let client = makeClient()
            let user: User = try await client.post("/users", body: NewUser(name: "Ada"), retry: instantRetry(3, nonIdempotent: true))
            #expect(user.id == 1)
            #expect(MockURLProtocol.requestCount == 2)
        }

        @Test func clientErrorsAreNotRetried() async {
            MockURLProtocol.reset(sequence: [.status(404), .json(userJSON(1))])
            let client = makeClient(retryPolicy: instantRetry(3))
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error?.statusCode == 404)
            #expect(MockURLProtocol.requestCount == 1)
        }

        @Test func connectivityErrorsAreRetried() async throws {
            MockURLProtocol.reset(sequence: [.failure(.networkConnectionLost), .json(userJSON(1))])
            let client = makeClient(retryPolicy: instantRetry(1))
            let user: User = try await client.get("/users/1")
            #expect(user.id == 1)
        }

        @Test func retryAfterIsHonored() async throws {
            MockURLProtocol.reset(sequence: [.status(429, headers: ["Retry-After": "0.3"]), .json(userJSON(1))])
            let client = makeClient(retryPolicy: instantRetry(1))
            let start = ContinuousClock.now
            let _: User = try await client.get("/users/1")
            #expect(ContinuousClock.now - start >= .milliseconds(300))
        }
    }
}
