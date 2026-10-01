# ``PerfectNetworkCalling``

A generic, type-safe networking layer built on `URLSession` and Swift concurrency.

## Overview

PerfectNetworkCalling sends HTTP requests and decodes their JSON responses into your
`Decodable` types. It handles the hard parts of networking for you:

- **GET, POST, PUT, PATCH and DELETE** with generic request bodies and response types.
- **Custom timeouts** for each request, enforced for the whole attempt.
- **Automatic retries** with exponential backoff, jitter and `Retry-After` support, never
  repeating a `POST` or `PATCH` unless you allow it.
- **Cancellation** through `Task.cancel()`, request tokens, cancellation keys or ``NetworkClient/cancelAll()``.
- **Many requests at once**, in order, with an optional concurrency limit.
- **Readable errors**: every failure is a ``NetworkError`` with a message you can show to users.
- **Interceptors** that change, observe or retry requests, including a console logger and an
  auth-token interceptor that refreshes the token only once.
- **Swift 6 data-race safety**: every public type is `Sendable`, and actor reentrancy is handled.

Requires iOS 17 or later.

```swift
import PerfectNetworkCalling

struct User: Codable, Sendable {
    let id: Int
    let name: String
}

let client = NetworkClient(baseURL: URL(string: "https://api.example.com")!)

let user: User = try await client.get("/users/1", timeout: 10)
let created: User = try await client.post("/users", body: User(id: 0, name: "Ada"))
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``NetworkClient``
- ``NetworkConfiguration``

### Making Requests

- <doc:MakingRequests>
- ``Endpoint``
- ``HTTPMethod``
- ``HTTPBody``
- ``EmptyResponse``

### Errors

- <doc:ErrorHandling>
- ``NetworkError``
- ``HTTPErrorResponse``

### Timeouts and Retries

- <doc:TimeoutsAndRetries>
- ``RetryPolicy``

### Cancellation

- <doc:Cancellation>
- ``RequestToken``

### Multiple Requests and Concurrency

- <doc:ConcurrentRequests>
- <doc:ConcurrencyAndReentrancy>

### Interceptors and Logging

- <doc:InterceptorsAndLogging>
- ``NetworkInterceptor``
- ``InterceptorRetryDecision``
- ``LoggingInterceptor``
- ``AuthInterceptor``
- ``AuthTokenProvider``
- ``TokenRefresher``

### Using the Client in Your App

- <doc:SwiftUIAndUIKitUsage>
