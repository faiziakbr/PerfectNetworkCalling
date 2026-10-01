# Getting Started

Create a client and send your first requests.

## Overview

Every request goes through a ``NetworkClient``. Create one client for each API your app talks
to, and share it, for example through a dependency container or a static property. The client
is `Sendable`, so you can use it from any task or actor.

### Create a client

The quickest way is to pass only the base URL:

```swift
let client = NetworkClient(baseURL: URL(string: "https://api.example.com/v1")!)
```

To change the defaults, pass a ``NetworkConfiguration``:

```swift
let client = NetworkClient(configuration: NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com/v1")!,
    defaultHeaders: ["X-Platform": "iOS"],
    timeout: 20,
    retryPolicy: .default,
    interceptors: [LoggingInterceptor()]
))
```

### Define your models

Response types must be `Decodable & Sendable`, and request bodies must be
`Encodable & Sendable`. Plain structs of `Sendable` values are `Sendable` automatically.

```swift
struct User: Decodable, Sendable {
    let id: Int
    let name: String
}

struct NewUser: Encodable, Sendable {
    let name: String
}
```

### Send requests

```swift
// GET
let user: User = try await client.get("/users/1")

// POST
let created: User = try await client.post("/users", body: NewUser(name: "Ada"))
```

When Swift can't infer the response type, pass it with `as:`:

```swift
let users = try await client.get("/users", as: [User].self)
```

### Handle errors

Every client method throws ``NetworkError`` and nothing else:

```swift
do {
    let user: User = try await client.get("/users/1")
} catch let error as NetworkError {
    print(error.errorDescription ?? "")      // "You appear to be offline."
    print(error.recoverySuggestion ?? "")    // "Check your Wi-Fi or mobile data connection and try again."
}
```

See <doc:ErrorHandling> for more.

### Logging

In `DEBUG` builds the client prints every request and response to the Xcode console through
``LoggingInterceptor``. Release builds don't log unless you add the interceptor yourself.
