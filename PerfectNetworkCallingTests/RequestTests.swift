//
//  RequestTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

extension MockedNetworkTests {
    @Suite("HTTP verbs")
    struct RequestVerbTests {
        @Test func getSendsQueryAndHeaders() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(1)) }
            let client = makeClient()
            let user: User = try await client.get("/users/1", query: ["expand": "all"], headers: ["X-Trace": "abc"])
            #expect(user == User(id: 1, name: "Ada"))
            let request = try #require(MockURLProtocol.requests.first)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://api.test.com/users/1?expand=all")
            #expect(request.value(forHTTPHeaderField: "X-Trace") == "abc")
            #expect(request.httpBody?.isEmpty ?? true)
        }

        @Test(arguments: [HTTPMethod.post, .put, .patch])
        func bodyVerbsSendJSON(method: HTTPMethod) async throws {
            MockURLProtocol.reset { _ in .json(userJSON(7, "Grace")) }
            let client = makeClient()
            let body = NewUser(name: "Grace")
            let user: User = switch method {
            case .post: try await client.post("/users", body: body)
            case .put: try await client.put("/users/7", body: body)
            default: try await client.patch("/users/7", body: body)
            }
            #expect(user == User(id: 7, name: "Grace"))
            let request = try #require(MockURLProtocol.requests.first)
            #expect(request.httpMethod == method.rawValue)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(try JSONDecoder().decode(NewUser.self, from: try #require(request.httpBody)) == body)
        }

        @Test func deleteWithNoContent() async throws {
            MockURLProtocol.reset { _ in .status(204) }
            let client = makeClient()
            let response: EmptyResponse = try await client.delete("/users/1")
            #expect(response == EmptyResponse())
            #expect(MockURLProtocol.requests.first?.httpMethod == "DELETE")
        }

        @Test func requestDataReturnsRawBody() async throws {
            MockURLProtocol.reset { _ in .json("hello") }
            let client = makeClient()
            let (data, response) = try await client.requestData(.get("/raw"))
            #expect(String(data: data, encoding: .utf8) == "hello")
            #expect(response.statusCode == 200)
        }

        @Test func invalidJSONThrowsDecodingFailed() async {
            MockURLProtocol.reset { _ in .json(#"{"id":"not a number"}"#) }
            let client = makeClient()
            let error = await networkError { let _: User = try await client.get("/users/1") }
            guard case .decodingFailed(let detail) = error else {
                Issue.record("Expected decodingFailed, got \(String(describing: error))")
                return
            }
            #expect(detail.contains("id"))
        }

        @Test func emptyBodyForNonEmptyTypeThrowsDecodingFailed() async {
            MockURLProtocol.reset { _ in .status(200) }
            let client = makeClient()
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error == .decodingFailed("The response body was empty, but User was expected."))
        }

        @Test(arguments: [(401, "unauthorized"), (404, "notFound"), (500, "serverError")])
        func httpErrorsAreMapped(status: Int, expectedCase: String) async {
            MockURLProtocol.reset { _ in .status(status, body: #"{"message":"Server says no"}"#) }
            let client = makeClient()
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error.map { String(describing: $0).hasPrefix(expectedCase) } == true)
            #expect(error?.statusCode == status)
            #expect(error?.httpResponse?.message == "Server says no")
        }

        @Test func offlineIsMapped() async {
            MockURLProtocol.reset { _ in .failure(.notConnectedToInternet) }
            let client = makeClient()
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error == .noInternetConnection)
            #expect(error?.errorDescription == "You appear to be offline.")
        }

        @Test func completionHandlerDeliversOnRequestedQueue() async throws {
            MockURLProtocol.reset { _ in .json(userJSON(3)) }
            let client = makeClient()
            let result: Result<User, NetworkError> = await withCheckedContinuation { continuation in
                client.send(.get("/users/3"), as: User.self) { result in
                    #expect(Thread.isMainThread)
                    continuation.resume(returning: result)
                }
            }
            #expect(try result.get().id == 3)
        }
    }

    @Suite("Timeouts")
    struct TimeoutTests {
        @Test func slowResponseTimesOut() async {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 2) }
            let client = makeClient(timeout: 10)
            let start = ContinuousClock.now
            let error = await networkError { let _: User = try await client.get("/users/1", timeout: 0.2) }
            #expect(error == .timedOut)
            #expect(ContinuousClock.now - start < .seconds(1.5))
        }

        @Test func clientDefaultTimeoutApplies() async {
            MockURLProtocol.reset { _ in .json(userJSON(1), delay: 2) }
            let client = makeClient(timeout: 0.2)
            let error = await networkError { let _: User = try await client.get("/users/1") }
            #expect(error == .timedOut)
        }

        @Test func timeoutIsRetriedForGet() async throws {
            MockURLProtocol.reset(sequence: [.json(userJSON(1), delay: 2), .json(userJSON(1))])
            let client = makeClient(timeout: 0.2, retryPolicy: instantRetry(1))
            let user: User = try await client.get("/users/1")
            #expect(user.id == 1)
            #expect(MockURLProtocol.requestCount == 2)
        }
    }
}
