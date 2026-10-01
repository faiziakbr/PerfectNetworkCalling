# Cancellation

Stop requests you no longer need.

## Overview

A cancelled request stops right away, including while it is waiting to retry, and throws
``NetworkError/cancelled``. There are four ways to cancel.

### Cancel the task

Requests follow Swift's structured concurrency: cancelling the task that awaits a request
cancels the request.

```swift
let task = Task {
    let user: User = try await client.get("/users/1")
    show(user)
}

// Later:
task.cancel()
```

SwiftUI's `.task` modifier cancels its task when the view disappears, so requests started
there are cancelled automatically:

```swift
.task {
    user = try? await client.get("/users/\(id)")
}
```

### Cancel with a request token

``NetworkClient/send(_:as:callbackQueue:completion:)`` returns a ``RequestToken``:

```swift
let token = client.send(.get("/feed"), as: Feed.self) { result in
    // Called exactly once, with .failure(.cancelled) if cancelled.
}

token.cancel()
```

### "Latest wins" with a cancellation key

When a new request replaces the previous one, as in search-as-you-type, give them the same
``Endpoint/cancellationKey``. Each new request cancels the one before it, so a slow, older
response can never overwrite a newer one:

```swift
func search(_ text: String) async {
    do {
        results = try await client.request(
            .get("/search", query: ["q": text]).cancelling(previousWithKey: "search")
        )
    } catch NetworkError.cancelled {
        // A newer search replaced this one.
    } catch {
        self.error = error
    }
}
```

You can also cancel by key from anywhere:

```swift
await client.cancel(key: "search")
```

### Cancel everything

``NetworkClient/cancelAll()`` cancels every in-flight request of the client, for example when
the user signs out:

```swift
await client.cancelAll()
```
