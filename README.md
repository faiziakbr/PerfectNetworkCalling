# PerfectNetworkCalling

A modern, generic, type-safe networking framework for Apple platforms built on `URLSession` and Swift 6 concurrency.

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg?style=flat)](https://developer.apple.com)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg?style=flat)](LICENSE)

---

## Overview

**PerfectNetworkCalling** takes care of the hard parts of iOS and macOS networking so you don't have to rebuild them in every project:

- 🛡️ **Swift 6 Strict Concurrency**: Fully data-race safe. Every public type is `Sendable`, and network operations and decoding execute off the `@MainActor` without stuttering your UI.
- ⚡ **Type-Safe Requests & Responses**: Seamless JSON encoding and decoding into your `Codable` models, with support for `EmptyResponse` (204 No Content), raw `Data`, and form URL encoding.
- ⏱️ **True Attempt Timeouts**: Timeouts govern the **entire attempt duration**, not just the interval between network packets.
- 🔁 **Resilient Automatic Retries**: Exponential backoff with random jitter, server `Retry-After` compliance, and safe idempotency safeguards (never repeating `POST` or `PATCH` unless explicitly allowed).
- 🛑 **Comprehensive Cancellation**: Cancel via standard Swift `Task.cancel()`, completion `RequestToken`, scoped cancellation keys (search-as-you-type), or global `cancelAll()`.
- 🔀 **In-Flight Request Deduplication**: Mark endpoints as `.deduplicated()` so concurrent identical `GET` requests share a single network call while maintaining independent caller continuations and cancellation.
- 📦 **Batch Concurrency**: Send multiple requests in parallel with `requestAll` (fail-fast) or `requestAllSettled` (collect all outcomes), strictly preserving order and supporting a `maxConcurrent` throttle.
- 💬 **Human-Readable Errors**: Unified `NetworkError` enum providing user-ready `errorDescription` and actionable `recoverySuggestion`, plus pinpointed decoding diagnostics with exact key paths.
- 🔌 **Extensible Interceptor Pipeline**: Transform, inspect, or retry requests. Includes `LoggingInterceptor` with emojis, cURL command output, header redaction, and `os.Logger` integration, and `AuthInterceptor` with actor-guaranteed single token refresh on `401 Unauthorized`.
- 📱 **SwiftUI & UIKit Ready**: Clean idioms for `@Observable` view models in SwiftUI and `RequestToken` completion closures in UIKit.

---

## Requirements

| Platform / Tool | Minimum Version |
|---|---|
| **Swift** | 6.2+ |
| **Xcode** | 16.0+ |
| **iOS** | 17.0+ |
| **macOS** | 14.0+ |

---

## Installation

### Swift Package Manager

#### In `Package.swift`:

Add `PerfectNetworkCalling` to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/PerfectNetworkCalling.git", from: "1.0.0")
]
```

And add it to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "PerfectNetworkCalling", package: "PerfectNetworkCalling")
    ]
)
```

#### In Xcode:

1. Open your project in Xcode.
2. Go to **File** > **Add Package Dependencies...**
3. Enter the repository URL.
4. Select the version rule and add `PerfectNetworkCalling` to your application target.

---

## Quick Start

```swift
import PerfectNetworkCalling
import Foundation

// 1. Define your models (must conform to Decodable/Encodable & Sendable)
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct CreateUserPayload: Encodable, Sendable {
    let name: String
    let email: String
}

// 2. Initialize a client
let client = NetworkClient(baseURL: URL(string: "https://api.example.com/v1")!)

// 3. Make requests
do {
    // GET request
    let user: User = try await client.get("/users/1")
    print("Fetched: \(user.name)")

    // POST request with body
    let payload = CreateUserPayload(name: "Ada Lovelace", email: "ada@example.com")
    let createdUser: User = try await client.post("/users", body: payload)
    print("Created ID: \(createdUser.id)")
} catch let error as NetworkError {
    print("Error: \(error.errorDescription ?? "")")
    print("Suggestion: \(error.recoverySuggestion ?? "")")
}
```

---

## Table of Contents

- [Client & Configuration](#client--configuration)
- [Making Requests](#making-requests)
  - [HTTP Verb Convenience Methods](#http-verb-convenience-methods)
  - [Endpoint Modeling](#endpoint-modeling)
  - [Request Bodies](#request-bodies)
  - [Query Parameters & Headers](#query-parameters--headers)
  - [Response Types](#response-types)
- [Error Handling](#error-handling)
  - [The `NetworkError` Enum](#the-networkerror-enum)
  - [User-Facing Error Messages](#user-facing-error-messages)
  - [Server Error Payloads (`HTTPErrorResponse`)](#server-error-payloads-httperrorresponse)
  - [Pinpointed Decoding Errors](#pinpointed-decoding-errors)
- [Timeouts & Retries](#timeouts--retries)
  - [Total-Attempt Timeouts](#total-attempt-timeouts)
  - [Retry Policies](#retry-policies)
  - [Exponential Backoff with Jitter](#exponential-backoff-with-jitter)
  - [Idempotency & Non-Idempotent Retries](#idempotency--non-idempotent-retries)
- [Concurrency & Cancellation](#concurrency--cancellation)
  - [Swift Task Cancellation](#swift-task-cancellation)
  - [Search-as-you-type ("Latest Wins" Cancellation Keys)](#search-as-you-type-latest-wins-cancellation-keys)
  - [Request Deduplication](#request-deduplication)
  - [Parallel Batches (`requestAll` & `requestAllSettled`)](#parallel-batches-requestall--requestallsettled)
  - [Completion Handlers & `RequestToken` (UIKit)](#completion-handlers--requesttoken-uikit)
- [Interceptors & Logging](#interceptors--logging)
  - [The `NetworkInterceptor` Protocol](#the-networkinterceptor-protocol)
  - [Logging Interceptor](#logging-interceptor)
  - [Authentication & Token Refresh](#authentication--token-refresh)
- [SwiftUI & UIKit Integration](#swiftui--uikit-integration)
  - [SwiftUI with `@Observable`](#swiftui-with-observable)
  - [UIKit Controller](#uikit-controller)
- [Testing & Mocking](#testing--mocking)
- [Architecture & Swift 6 Safety](#architecture--swift-6-safety)

---

## Client & Configuration

Create one `NetworkClient` per base API and share it across your app. Clients are `Sendable` and thread-safe.

```swift
let configuration = NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com/v1")!,
    defaultHeaders: [
        "X-App-Platform": "iOS",
        "X-App-Version": "2.1.0"
    ],
    timeout: 20,                               // 20s attempt timeout
    resourceTimeout: 300,                      // Session transfer limit
    retryPolicy: .default,                     // Automatic retries
    interceptors: [
        AuthInterceptor(tokenProvider: sessionStore),
        LoggingInterceptor(level: .body)
    ],
    encoder: JSONEncoder(),                    // Custom JSONEncoder
    decoder: {                                 // Custom JSONDecoder
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
)

let client = NetworkClient(configuration: configuration)
```

In `DEBUG` builds, `NetworkConfiguration` automatically includes a `LoggingInterceptor()`. In `RELEASE` builds, default interceptors are empty.

---

## Making Requests

### HTTP Verb Convenience Methods

`NetworkClient` provides high-level convenience methods for standard HTTP verbs:

```swift
// GET
let user: User = try await client.get("/users/1", query: ["include": "profile"])

// POST
let created: User = try await client.post("/users", body: newUserData)

// PUT
let replaced: User = try await client.put("/users/1", body: user)

// PATCH
let patched: User = try await client.patch("/users/1", body: ["name": "Ada"])

// DELETE (defaults to EmptyResponse)
try await client.delete("/users/1")
```

Every verb method accepts optional `headers`, `timeout`, and `retry` parameters to override configuration defaults for that single call.

### Endpoint Modeling

An `Endpoint` is an immutable, `Sendable` description of a request. It does not touch the network until passed to the client:

```swift
let endpoint = Endpoint.get("/search", query: ["q": "swift"], timeout: 10)
let results = try await client.request(endpoint, as: [SearchResult].self)
```

#### Organizing APIs with Endpoint Extensions

A recommended pattern is to organize your endpoints in static factory extensions:

```swift
extension Endpoint {
    static func user(id: Int) -> Endpoint {
        .get("/users/\(id)")
    }
    
    static func updateUser(id: Int, profile: UserProfile) -> Endpoint {
        .put("/users/\(id)", body: profile)
    }
    
    static func search(query: String) -> Endpoint {
        .get("/search", query: ["q": query])
            .cancelling(previousWithKey: "search")
    }
}

// Usage:
let user: User = try await client.request(.user(id: 42))
```

### Request Bodies

The `HTTPBody` enum supports multiple payload representations:

```swift
// 1. Encodable JSON model
let jsonBody: HTTPBody = .json(newUser)

// 2. Form URL Encoded (application/x-www-form-urlencoded)
let formBody: HTTPBody = .formURLEncoded([
    "grant_type": "password",
    "username": "user@example.com"
])

// 3. Raw Data with custom content type
let rawBody: HTTPBody = .data(imagePNGData, contentType: "image/png")

// Using with Endpoint:
let upload = Endpoint(
    path: "/upload",
    method: .post,
    body: rawBody
)
```

### Query Parameters & Headers

- **Deterministic URL generation**: Query parameter keys are automatically sorted alphabetically, ensuring consistent caching and request signatures.
- **Percent Encoding**: Special characters like `+` in query values are correctly encoded as `%2B` so receiving servers don't mistakenly parse them as spaces.
- **Header Precedence**: Headers are merged in order:
  1. `Accept: application/json` (default)
  2. `NetworkConfiguration.defaultHeaders`
  3. `Endpoint.headers`
  4. Interceptors (e.g. `AuthInterceptor`)

### Response Types

| Requested Type | Client Behavior |
|---|---|
| `T: Decodable & Sendable` | Decodes the JSON response body using `configuration.decoder`. |
| `EmptyResponse` | Discards the response body. Perfect for `204 No Content` or `200 OK` without payloads. |
| `Data` | Returns the raw response `Data` without decoding. |

To inspect response headers or status codes alongside data, use `requestData(_:)`:

```swift
let (data, response) = try await client.requestData(.get("/download"))
let etag = response.value(forHTTPHeaderField: "ETag")
```

---

## Error Handling

### The `NetworkError` Enum

All `NetworkClient` methods throw `NetworkError` exclusively. You never need to catch unhandled `URLError` or raw decoding errors.

```swift
do {
    let profile: Profile = try await client.get("/me")
} catch NetworkError.unauthorized {
    sessionStore.signOut()
} catch NetworkError.noInternetConnection {
    showOfflineBanner()
} catch NetworkError.cancelled {
    // Task was cancelled, ignore
} catch let error as NetworkError {
    showBanner(title: error.errorDescription, message: error.recoverySuggestion)
}
```

#### Error Categories

- **Request Preparation**: `.invalidURL(path)`, `.encodingFailed(reason)`
- **Connectivity**: `.noInternetConnection`, `.connectionLost`, `.cannotConnectToHost`, `.sslError`, `.timedOut`, `.cancelled`
- **HTTP Status Codes**: `.badRequest(400)`, `.unauthorized(401)`, `.forbidden(403)`, `.notFound(404)`, `.conflict(409)`, `.unprocessableEntity(422)`, `.rateLimited(429)`, `.clientError(4xx)`, `.serverError(5xx)`, `.unexpectedStatus`
- **Response Handling**: `.invalidResponse`, `.decodingFailed(reason)`, `.unknown(message)`

### User-Facing Error Messages

`NetworkError` implements `LocalizedError`:

- `errorDescription`: Plain-language explanation for users (e.g. *"You appear to be offline."* or the server's own message for `4xx`).
- `recoverySuggestion`: Recommended action (e.g. *"Check your Wi-Fi or mobile data connection and try again."*).
- `failureReason`: Technical diagnostic string for logging (e.g. `"HTTP 503"` or decoding failure paths).

### Server Error Payloads (`HTTPErrorResponse`)

HTTP-status error cases hold an `HTTPErrorResponse` containing `statusCode`, `headers`, raw `data`, and extracted `message`:

```swift
struct APIValidationError: Decodable {
    let errorField: String
    let issue: String
}

do {
    let user: User = try await client.post("/users", body: payload)
} catch let NetworkError.unprocessableEntity(response) {
    if let validation = try? response.decode(APIValidationError.self) {
        print("Field error: \(validation.errorField): \(validation.issue)")
    }
}
```

The client automatically extracts error messages from common JSON structures (`message`, `error_description`, `detail`, `error`, `title`, or error arrays) without manual parsing.

### Pinpointed Decoding Errors

When JSON decoding fails, `NetworkError.decodingFailed` produces descriptive messages highlighting the exact field and reason:

```text
Missing key 'email' at users[0].email.
Type mismatch at user.age: expected Int. Expected to decode Int but found a string instead.
```

---

## Timeouts & Retries

### Total-Attempt Timeouts

Standard `URLRequest.timeoutInterval` only measures the idle time between data packets; a trickling response could take several minutes without timing out.

**PerfectNetworkCalling enforces timeouts across the entire attempt.** If the server does not deliver the full response within the specified duration, the attempt is cancelled and `NetworkError.timedOut` is thrown.

```swift
// Client-wide default
let client = NetworkClient(configuration: .init(baseURL: url, timeout: 15))

// Per-request timeout override
let result: Data = try await client.get("/large-report", timeout: 60)
```

### Retry Policies

Control automatic retries using `RetryPolicy`:

```swift
// Use presets:
.none        // 0 retries
.default     // Up to 3 retries, starting at 0.5s up to 10s
.aggressive  // Up to 5 retries, starting at 0.25s up to 30s

// Or build a custom policy:
let customPolicy = RetryPolicy(
    maxRetries: 4,
    baseDelay: 1.0,
    multiplier: 2.0,
    maxDelay: 15.0,
    jitter: 0.25,
    retryableStatusCodes: [408, 429, 500, 502, 503, 504],
    retryOnTimeout: true,
    retryOnConnectivityErrors: true,
    retryNonIdempotent: false,
    respectsRetryAfter: true,
    maxRetryAfter: 60.0
)
```

### Exponential Backoff with Jitter

Retries calculate backoff delays using:
$$\text{delay} = \min(\text{baseDelay} \times \text{multiplier}^{n-1},\; \text{maxDelay}) \times (1 \pm \text{jitter})$$

Jitter decorrelates concurrent clients retrying after an outage, protecting backend infrastructure from thundering herds.

When a server sends a `Retry-After` header (seconds or RFC 7231 HTTP-date), the client honors that delay up to `maxRetryAfter`.

### Idempotency & Non-Idempotent Retries

By default, only idempotent HTTP methods (`GET`, `PUT`, `DELETE`) are retried.

`POST` and `PATCH` requests are **not** retried automatically to prevent duplicate records (such as accidental double purchases). You can opt into retries when using idempotency keys:

```swift
var policy = RetryPolicy.default
policy.retryNonIdempotent = true

let order: Order = try await client.post(
    "/orders",
    body: cart,
    headers: ["Idempotency-Key": cart.id.uuidString],
    retry: policy
)
```

---

## Concurrency & Cancellation

### Swift Task Cancellation

Requests participate in structured concurrency. Cancelling the parent `Task` immediately halts in-flight network activity and aborts any active retry backoff sleep:

```swift
let task = Task {
    let feed: [Post] = try await client.get("/feed")
    display(feed)
}

// Later:
task.cancel() // Request terminates with NetworkError.cancelled
```

### Search-as-you-type ("Latest Wins" Cancellation Keys)

When multiple sequential requests target the same logical resource (e.g. search suggestions), tag the endpoint with `cancellationKey`:

```swift
func search(query: String) async {
    do {
        let endpoint = Endpoint.get("/search", query: ["q": query])
            .cancelling(previousWithKey: "search")
            
        let results: [SearchResult] = try await client.request(endpoint)
        self.results = results
    } catch NetworkError.cancelled {
        // A newer keystroke launched a replacement request; silently ignore.
    } catch {
        self.error = error
    }
}
```

Whenever a new request with key `"search"` starts, any prior in-flight search request is automatically cancelled.

You can also cancel by key manually:

```swift
await client.cancel(key: "search")
```

### Request Deduplication

Prevent duplicate concurrent requests for the same read resource across your app with `.deduplicated()`:

```swift
let endpoint = Endpoint.get("/me").deduplicated()

// Called simultaneously from two independent views:
async let userA: User = client.request(endpoint)
async let userB: User = client.request(endpoint)

let (profile1, profile2) = try await (userA, userB)
```

Both callers await the same network call. If one caller cancels its task, the underlying network call continues for the second caller unless **all** callers cancel.

### Parallel Batches (`requestAll` & `requestAllSettled`)

Execute lists of endpoints concurrently while guaranteeing that results match the order of the input array.

#### Fail-Fast (`requestAll`)

Cancels all remaining requests upon the first failure:

```swift
let ids = [101, 102, 103, 104]
let endpoints = ids.map { Endpoint.get("/items/\($0)") }

// Limited to at most 2 concurrent requests
let items: [Item] = try await client.requestAll(endpoints, maxConcurrent: 2)
```

#### Collect All Outcomes (`requestAllSettled`)

Never throws; returns an array of `Result<T, NetworkError>`:

```swift
let outcomes = await client.requestAllSettled(endpoints, as: Item.self, maxConcurrent: 4)

for (id, result) in zip(ids, outcomes) {
    switch result {
    case .success(let item):
        print("Loaded \(id): \(item.name)")
    case .failure(let error):
        print("Failed \(id): \(error.errorDescription ?? "")")
    }
}
```

#### Global Cancellation

Cancel every active in-flight request on a client (e.g. on user sign-out):

```swift
await client.cancelAll()
```

### Completion Handlers & `RequestToken` (UIKit)

For legacy or UIKit code that does not use `async/await`, use `send`:

```swift
let token: RequestToken = client.send(.get("/feed"), as: [Post].self) { [weak self] result in
    switch result {
    case .success(let posts):
        self?.updateUI(posts)
    case .failure(.cancelled):
        break
    case .failure(let error):
        self?.showError(error)
    }
}

// Cancel when view controller deinitializes
token.cancel()
```

The completion handler is called on `DispatchQueue.main` by default.

---

## Interceptors & Logging

### The `NetworkInterceptor` Protocol

Interceptors observe, mutate, or retry requests throughout their lifecycle:

```swift
public protocol NetworkInterceptor: Sendable {
    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest
    func willSend(_ request: URLRequest, attempt: Int) async
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest, duration: Duration) async
    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async
    func retryDecision(for request: URLRequest, dueTo error: NetworkError, attempt: Int) async -> InterceptorRetryDecision
}
```

All methods have default no-op implementations, so you only implement what you need.

#### Custom Interceptor Example

```swift
struct CustomHeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
        var req = request
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        return req
    }
    
    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async {
        AnalyticsService.shared.trackNetworkError(error, url: request.url)
    }
}
```

### Logging Interceptor

`LoggingInterceptor` provides rich, readable diagnostics in the Xcode console and macOS Console.app.

```swift
LoggingInterceptor(
    level: .body,                                    // .none, .basic, .headers, .body
    maxBodyLength: 4_000,                            // Truncates oversized bodies
    redactedHeaders: ["Authorization", "X-Api-Key"], // Masked as ***
    includesCURL: true                               // Generates ready-to-run curl snippet
)
```

#### Example Output

```text
⬆️ POST https://api.example.com/v1/users (attempt 1)
Headers:
  Accept: application/json
  Authorization: ***
  Content-Type: application/json
Body:
{
  "email" : "ada@example.com",
  "name" : "Ada Lovelace"
}
cURL:
curl -X POST 'https://api.example.com/v1/users' -H 'Accept: application/json' -H 'Authorization: ***' -H 'Content-Type: application/json' --data-raw '{"name":"Ada Lovelace","email":"ada@example.com"}'

✅ 201 POST https://api.example.com/v1/users (142 ms)
Headers:
  Content-Type: application/json
Body:
{
  "id" : 42,
  "name" : "Ada Lovelace"
}
```

### Authentication & Token Refresh

`AuthInterceptor` automatically injects `Authorization: Bearer <token>` into requests. When an endpoint returns `401 Unauthorized`, it coordinates a safe token refresh through `AuthTokenProvider`:

```swift
actor SessionManager: AuthTokenProvider {
    private var accessToken: String?
    private var refreshToken: String?

    func token() async throws -> String? {
        accessToken
    }

    func refreshToken() async throws -> String {
        let newTokens = try await AuthAPI.refreshToken(refreshToken)
        self.accessToken = newTokens.access
        self.refreshToken = newTokens.refresh
        return newTokens.access
    }
}

// Attach to client configuration:
let authInterceptor = AuthInterceptor(tokenProvider: sessionManager)
```

#### Concurrency & Reentrancy Safety
If 10 concurrent requests fail with `401 Unauthorized` simultaneously, `TokenRefresher` guarantees **exactly one** refresh operation takes place. All other waiting requests await that same task and retry seamlessly once the fresh token is obtained.

---

## SwiftUI & UIKit Integration

### SwiftUI with `@Observable`

```swift
import SwiftUI
import Observation
import PerfectNetworkCalling

@MainActor
@Observable
final class UserListViewModel {
    private let client: NetworkClient
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?

    init(client: NetworkClient = .shared) {
        self.client = client
    }

    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            users = try await client.get("/users")
            errorMessage = nil
        } catch NetworkError.cancelled {
            // View disappeared; do nothing
        } catch let error as NetworkError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UserListView: View {
    @State private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.users, id: \.id) { user in
                Text(user.name)
            }
            .navigationTitle("Users")
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            // Automatically starts on appear and cancels on disappear
            .task {
                await viewModel.loadUsers()
            }
            .refreshable {
                await viewModel.loadUsers()
            }
        }
    }
}
```

### UIKit Controller

```swift
import UIKit
import PerfectNetworkCalling

final class ProfileViewController: UIViewController {
    private var requestToken: RequestToken?
    private let client: NetworkClient = .shared

    override func viewDidLoad() {
        super.viewDidLoad()
        loadProfile()
    }

    private func loadProfile() {
        requestToken = client.send(.get("/me"), as: UserProfile.self) { [weak self] result in
            switch result {
            case .success(let profile):
                self?.render(profile)
            case .failure(.cancelled):
                break
            case .failure(let error):
                self?.presentAlert(title: error.errorDescription, message: error.recoverySuggestion)
            }
        }
    }

    deinit {
        requestToken?.cancel()
    }
}
```

---

## Testing & Mocking

`NetworkClient` accepts custom `URLSession` instances, making it straightforward to test endpoints with `URLProtocol` mocking without hitting live servers:

```swift
final class MockURLProtocol: URLProtocol {
    static var mockHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.mockHandler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// In unit tests:
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)

let client = NetworkClient(
    configuration: NetworkConfiguration(baseURL: URL(string: "https://test.example.com")!),
    session: session
)

MockURLProtocol.mockHandler = { request in
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let json = #"{"id": 1, "name": "Test User"}"#.data(using: .utf8)!
    return (response, json)
}

let user: User = try await client.get("/users/1")
#expect(user.name == "Test User")
```

---

## Architecture & Swift 6 Safety

PerfectNetworkCalling is built from the ground up for modern Swift concurrency:

1. **Compilation in Swift 6 Language Mode**: Verified with strict concurrency checks enabled (`Sendable` enforcement, non-isolated default rules).
2. **Actor Reentrancy Hardening**:
   - `TaskRegistry` keeps synchronous mutation blocks to ensure cancellation keys and cleanup never interleave unpredictably.
   - `TokenRefresher` captures refresh tasks before awaiting, preventing duplicate token refresh races.
   - `RequestDeduplicator` registers continuations synchronously before suspending.
3. **Background Execution**:
   - Async request functions are marked `@concurrent`, guaranteeing that URLSession task setup, network transfer waits, and JSON decoding execute outside the `@MainActor`. UI updates remain smooth and responsive.

---

## License

PerfectNetworkCalling is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
