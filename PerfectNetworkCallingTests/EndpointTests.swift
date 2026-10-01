//
//  EndpointTests.swift
//  PerfectNetworkCallingTests
//

import Foundation
import Testing
@testable import PerfectNetworkCalling

@Suite("HTTPMethod")
struct HTTPMethodTests {
    @Test(arguments: [(HTTPMethod.get, true), (.put, true), (.delete, true), (.post, false), (.patch, false)])
    func idempotency(method: HTTPMethod, expected: Bool) {
        #expect(method.isIdempotent == expected)
    }

    @Test func rawValuesAreUppercaseVerbs() {
        #expect(HTTPMethod.allCases.map(\.rawValue) == ["GET", "POST", "PUT", "PATCH", "DELETE"])
    }
}

@Suite("Endpoint")
struct EndpointTests {
    @Test func appendsPathToBaseURL() throws {
        let request = try Endpoint.get("/users/1").urlRequest(baseURL: URL(string: "https://api.test.com/v1")!)
        #expect(request.url?.absoluteString == "https://api.test.com/v1/users/1")
        #expect(request.httpMethod == "GET")
    }

    @Test func absolutePathIgnoresBaseURL() throws {
        let request = try Endpoint.get("https://cdn.test.com/file.json").urlRequest(baseURL: testBaseURL)
        #expect(request.url?.absoluteString == "https://cdn.test.com/file.json")
    }

    @Test func queryIsSortedAndEncoded() throws {
        let request = try Endpoint.get("/search", query: ["q": "swift ui+combine", "page": "2"]).urlRequest(baseURL: testBaseURL)
        #expect(request.url?.absoluteString == "https://api.test.com/search?page=2&q=swift%20ui%2Bcombine")
    }

    @Test func endpointHeadersOverrideDefaults() throws {
        let request = try Endpoint.get("/x", headers: ["X-Mode": "endpoint", "Accept": "text/plain"])
            .urlRequest(baseURL: testBaseURL, defaultHeaders: ["X-Mode": "default", "X-App": "1"])
        #expect(request.value(forHTTPHeaderField: "X-Mode") == "endpoint")
        #expect(request.value(forHTTPHeaderField: "X-App") == "1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
    }

    @Test func jsonBodySetsContentType() throws {
        let request = try Endpoint.post("/users", body: NewUser(name: "Ada")).urlRequest(baseURL: testBaseURL)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode(NewUser.self, from: try #require(request.httpBody))
        #expect(body == NewUser(name: "Ada"))
    }

    @Test func formBodyIsURLEncoded() throws {
        let endpoint = Endpoint(path: "/token", method: .post, body: .formURLEncoded(["user": "a b", "grant_type": "password&x"]))
        let request = try endpoint.urlRequest(baseURL: testBaseURL)
        #expect(String(data: try #require(request.httpBody), encoding: .utf8) == "grant_type=password%26x&user=a+b")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded") == true)
    }

    @Test func timeoutOverridesDefault() throws {
        #expect(try Endpoint.get("/x", timeout: 7).urlRequest(baseURL: testBaseURL, defaultTimeout: 30).timeoutInterval == 7)
        #expect(try Endpoint.get("/x").urlRequest(baseURL: testBaseURL, defaultTimeout: 30).timeoutInterval == 30)
    }

    @Test func unencodableBodyThrowsEncodingFailed() {
        struct Bad: Encodable, Sendable {
            func encode(to encoder: any Encoder) throws {
                throw EncodingError.invalidValue(Double.nan, .init(codingPath: [], debugDescription: "NaN"))
            }
        }
        #expect {
            try Endpoint.post("/x", body: Bad()).urlRequest(baseURL: testBaseURL)
        } throws: { error in
            if case NetworkError.encodingFailed = error { true } else { false }
        }
    }

    @Test func modifiers() {
        let endpoint = Endpoint.get("/x").deduplicated().cancelling(previousWithKey: "search")
        #expect(endpoint.deduplicate)
        #expect(endpoint.cancellationKey == "search")
    }
}
