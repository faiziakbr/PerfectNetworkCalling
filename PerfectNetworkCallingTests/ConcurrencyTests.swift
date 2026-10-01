//
//  ConcurrencyTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

extension MockedNetworkTests {
    @Suite("Cancellation")
    struct CancellationTests {
        @Test func cancellingTaskCancelsRequest() async {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 2) }
            let client = makeClient()
            let task = Task { let _: User = try await client.get("/users/1") }
            try? await Task.sleep(for: .milliseconds(100))
            task.cancel()
            let start = ContinuousClock.now
            let error = await networkError { try await task.value }
            #expect(error == .cancelled)
            #expect(ContinuousClock.now - start < .seconds(1))
        }

        @Test func requestTokenCancels() async {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 2) }
            let client = makeClient()
            let result: Result<User, NetworkError> = await withCheckedContinuation { continuation in
                let token = client.send(.get("/users/1"), as: User.self) { continuation.resume(returning: $0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { token.cancel() }
            }
            #expect(throws: NetworkError.cancelled) { try result.get() }
        }

        @Test func cancelAllCancelsEveryRequest() async {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 2) }
            let client = makeClient()
            let tasks = (1...3).map { id in Task { let _: User = try await client.get("/users/\(id)") } }
            try? await Task.sleep(for: .milliseconds(150))
            #expect(await client.activeRequestCount == 3)
            await client.cancelAll()
            for task in tasks {
                #expect(await networkError { try await task.value } == .cancelled)
            }
            #expect(await client.activeRequestCount == 0)
        }

        @Test func cancellingDuringBackoffStopsRetries() async {
            MockURLProtocol.reset { _ in .status(503) }
            let client = makeClient(retryPolicy: RetryPolicy(maxRetries: 5, baseDelay: 1, jitter: 0))
            let task = Task { let _: User = try await client.get("/users/1") }
            try? await Task.sleep(for: .milliseconds(200))
            task.cancel()
            #expect(await networkError { try await task.value } == .cancelled)
            try? await Task.sleep(for: .milliseconds(1200))
            #expect(MockURLProtocol.requestCount == 1)
        }
    }

    @Suite("Multiple requests")
    struct MultipleRequestTests {
        @Test func asyncLetRunsInParallel() async throws {
            MockURLProtocol.reset { request in
                .json(userJSON(Int(request.url!.lastPathComponent)!), delay: 0.3)
            }
            let client = makeClient()
            let start = ContinuousClock.now
            async let first: User = client.get("/users/1")
            async let second: User = client.get("/users/2")
            let (a, b) = try await (first, second)
            #expect(a.id == 1 && b.id == 2)
            #expect(ContinuousClock.now - start < .milliseconds(550))
        }

        @Test func requestAllPreservesOrder() async throws {
            // Later requests answer sooner, so completion order is the reverse of input order.
            MockURLProtocol.reset { request in
                let id = Int(request.url!.lastPathComponent)!
                return .json(userJSON(id), delay: 0.05 * Double(6 - id))
            }
            let client = makeClient()
            let users = try await client.requestAll((1...5).map { .get("/users/\($0)") }, as: User.self)
            #expect(users.map(\.id) == [1, 2, 3, 4, 5])
        }

        @Test func requestAllFailsFastAndCancelsTheRest() async {
            MockURLProtocol.reset { request in
                request.url!.lastPathComponent == "2" ? .status(404) : .json(userJSON(1), delay: 2)
            }
            let client = makeClient()
            let start = ContinuousClock.now
            let error = await networkError {
                _ = try await client.requestAll((1...3).map { .get("/users/\($0)") }, as: User.self)
            }
            #expect(error?.statusCode == 404)
            #expect(ContinuousClock.now - start < .seconds(1))
        }

        @Test func requestAllSettledReturnsEveryOutcome() async {
            MockURLProtocol.reset { request in
                request.url!.lastPathComponent == "2" ? .status(404) : .json(userJSON(Int(request.url!.lastPathComponent)!))
            }
            let client = makeClient()
            let results = await client.requestAllSettled((1...3).map { .get("/users/\($0)") }, as: User.self)
            #expect(results.count == 3)
            #expect((try? results[0].get())?.id == 1)
            #expect(results[1].error?.statusCode == 404)
            #expect((try? results[2].get())?.id == 3)
        }

        @Test func maxConcurrentLimitsInFlightRequests() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 0.1) }
            let client = makeClient()
            _ = try await client.requestAll((1...6).map { .get("/users/\($0)") }, as: User.self, maxConcurrent: 2)
            #expect(MockURLProtocol.requestCount == 6)
            #expect(MockURLProtocol.peakActive == 2)
        }

        @Test func emptyInputReturnsEmpty() async throws {
            let client = makeClient()
            #expect(try await client.requestAll([], as: User.self).isEmpty)
            #expect(await client.requestAllSettled([], as: User.self).isEmpty)
        }
    }

    @Suite("Reentrancy")
    struct ReentrancyTests {
        @Test func concurrentUnauthorizedRequestsShareOneRefresh() async {
            MockURLProtocol.reset { request in
                request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token"
                    ? .json(userJSON(1), delay: 0.02)
                    : .status(401, delay: 0.02)
            }
            let provider = CountingTokenProvider(initial: "old-token")
            let client = makeClient(interceptors: [AuthInterceptor(tokenProvider: provider)])
            let results = await client.requestAllSettled(Array(repeating: Endpoint.get("/me"), count: 10), as: User.self)
            #expect(results.allSatisfy { (try? $0.get()) != nil })
            #expect(await provider.refreshCount == 1)
        }

        @Test func failedRefreshReturnsUnauthorized() async {
            MockURLProtocol.reset { _ in .status(401) }
            let provider = CountingTokenProvider(initial: "old-token", failRefresh: true)
            let client = makeClient(interceptors: [AuthInterceptor(tokenProvider: provider)])
            let error = await networkError { let _: User = try await client.get("/me") }
            #expect(error?.statusCode == 401)
            #expect(await provider.refreshCount == 1)
        }

        @Test func deduplicatedRequestsShareOneNetworkCall() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 0.2) }
            let client = makeClient()
            let users = try await client.requestAll(Array(repeating: Endpoint.get("/users/1").deduplicated(), count: 5), as: User.self)
            #expect(users.count == 5)
            #expect(MockURLProtocol.requestCount == 1)
        }

        @Test func cancellingOneDeduplicatedCallerKeepsOthersRunning() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 0.3) }
            let client = makeClient()
            let endpoint = Endpoint.get("/users/1").deduplicated()
            let cancelled = Task { let _: User = try await client.request(endpoint) }
            let kept = Task { try await client.request(endpoint, as: User.self) }
            try await Task.sleep(for: .milliseconds(100))
            cancelled.cancel()
            #expect(await networkError { try await cancelled.value } == .cancelled)
            #expect(try await kept.value.id == 1)
            #expect(MockURLProtocol.requestCount == 1)
        }

        @Test func cancellationKeyDeliversOnlyLatest() async throws {
            MockURLProtocol.reset { request in
                .json(userJSON(Int(request.url!.lastPathComponent)!), delay: 0.4)
            }
            let client = makeClient()
            var tasks: [Task<User, any Error>] = []
            for id in 1...3 {
                tasks.append(Task { try await client.request(.get("/users/\(id)").cancelling(previousWithKey: "search")) })
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(await networkError { _ = try await tasks[0].value } == .cancelled)
            #expect(await networkError { _ = try await tasks[1].value } == .cancelled)
            #expect(try await tasks[2].value.id == 3)
        }
    }
}

private extension Result {
    var error: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
