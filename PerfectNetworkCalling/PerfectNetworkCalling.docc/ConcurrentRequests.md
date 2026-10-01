# Multiple Requests at Once

Send several requests in parallel and collect their responses.

## Overview

### Different response types: async let

Use `async let` to run requests with different response types at the same time:

```swift
async let profile: Profile = client.get("/me")
async let feed: [Post] = client.get("/feed")
async let notifications: [Notice] = client.get("/notifications")

let (me, posts, notices) = try await (profile, feed, notifications)
```

If one fails, the error is thrown and the others are cancelled.

### Same response type: requestAll

``NetworkClient/requestAll(_:as:maxConcurrent:)`` sends a list of endpoints in parallel and
returns the responses **in the same order as the endpoints**, however the responses arrive:

```swift
let ids = [4, 8, 15, 16, 23, 42]
let users = try await client.requestAll(ids.map { .get("/users/\($0)") }, as: User.self)
// users[0] is user 4, users[1] is user 8, ...
```

It fails fast: the first error is thrown and the remaining requests are cancelled.

### Keep every outcome: requestAllSettled

When some requests may fail and you still want the others, use
``NetworkClient/requestAllSettled(_:as:maxConcurrent:)``. It never throws, and returns one
`Result` per endpoint, in order:

```swift
let results = await client.requestAllSettled(ids.map { .get("/users/\($0)") }, as: User.self)

for (id, result) in zip(ids, results) {
    switch result {
    case .success(let user): print(user.name)
    case .failure(let error): print("User \(id) failed: \(error.errorDescription ?? "")")
    }
}
```

### Limiting concurrency

Pass `maxConcurrent` to keep only a few requests in flight at once. When one finishes, the next
starts. This is useful for large batches, or for servers with strict rate limits:

```swift
let thumbnails = try await client.requestAll(endpoints, as: Data.self, maxConcurrent: 4)
```

### Sharing identical requests

If several parts of your app ask for the same resource at the same moment, mark the endpoint
as ``Endpoint/deduplicated()``. Identical in-flight `GET` requests then share one network call:

```swift
let me: Profile = try await client.request(.get("/me").deduplicated())
```

See <doc:ConcurrencyAndReentrancy> for how this works.
