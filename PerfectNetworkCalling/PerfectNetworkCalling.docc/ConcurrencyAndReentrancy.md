# Concurrency and Reentrancy

How the client stays free of data races in Swift 6, and how it handles actor reentrancy.

## Overview

The framework compiles in the Swift 6 language mode, which checks for data races at compile
time. Every public type is `Sendable`, so you can pass clients, endpoints, errors and tokens
between tasks and actors freely.

### Off the main actor

The client's async methods are marked `@concurrent`. Calling them from a `@MainActor` view
model runs the network work and JSON decoding on a background thread, then returns the result
to the caller's actor. Large responses never block the UI.

### What your types need

- Response types must be `Decodable & Sendable`.
- Request bodies must be `Encodable & Sendable`.
- Interceptors and token providers must be `Sendable`. Keep mutable state inside an `actor`.

### Actor reentrancy

When an actor method reaches an `await`, the actor can run other calls before that method
resumes. If the method checked some state before the `await`, that state may have changed
afterwards. This is *actor reentrancy*, and it causes subtle bugs, such as refreshing a token
twice. The framework handles it in four places.

**Request tracking.** The actor that tracks in-flight requests for ``NetworkClient/cancelAll()``
and cancellation keys has only synchronous methods. Each one finishes before another can start,
so a request that ends during `cancelAll()` can't leave a stale entry behind or be removed twice.

**Token refresh.** ``TokenRefresher`` stores the in-flight refresh as a `Task` before it awaits
anything. Requests that fail with `401` while the refresh runs await that same task instead of
starting their own. A request that was sent with an old token, and fails after the refresh
finished, uses the new token without refreshing again. The result: one refresh, however many
requests fail together.

**Request deduplication.** For ``Endpoint/deduplicate``d requests, each caller waits on its own
continuation, registered in the same synchronous step that checks for cancellation. One caller
can cancel without affecting the others, and the shared network call is cancelled only when every
caller has cancelled. Each shared call has its own ID, so a call that finishes late can never
remove a newer call for the same URL.

**Cancellation keys.** A new request with the same ``Endpoint/cancellationKey`` cancels the
previous one in the same synchronous step that registers the new one, so there's never a moment
when both are delivered.

### Cancellation in retries

The retry loop checks for cancellation before every attempt, and waits for backoff delays with
`Task.sleep`, which throws as soon as the task is cancelled. A cancelled request is never sent again.
