# Timeouts and Retries

Limit how long requests take, and retry them automatically when failures are temporary.

## Overview

### Timeouts

Each attempt is limited by ``Endpoint/timeout``, or ``NetworkConfiguration/timeout`` if the
endpoint doesn't set one. The default is 30 seconds.

```swift
// The whole client
let client = NetworkClient(configuration: .init(baseURL: baseURL, timeout: 15))

// One request
let quote: Quote = try await client.get("/quote", timeout: 3)
```

The timeout limits the **whole attempt**, not only the time between packets as
`URLRequest.timeoutInterval` does, so a slow, trickling response still times out on time.
When it does, the request throws ``NetworkError/timedOut``. Each retry gets the full timeout again.

### Retry policies

A ``RetryPolicy`` decides which failures are retried and how long to wait in between.

| Preset | Retries | First delay | Longest delay |
|---|---|---|---|
| ``RetryPolicy/none`` | 0 | none | none |
| ``RetryPolicy/default`` | 3 | 0.5 s | 10 s |
| ``RetryPolicy/aggressive`` | 5 | 0.25 s | 30 s |

By default these failures are retried:

- Timeouts.
- Connectivity errors: offline, connection lost, host unreachable.
- Status codes `408`, `429`, `500`, `502`, `503` and `504`.

Set the policy for the whole client, or for one request:

```swift
let client = NetworkClient(configuration: .init(baseURL: baseURL, retryPolicy: .default))

let feed: Feed = try await client.get("/feed", retry: .aggressive)
let ping: Pong = try await client.get("/ping", retry: RetryPolicy.none)
```

Build your own:

```swift
let policy = RetryPolicy(
    maxRetries: 4,
    baseDelay: 1,
    multiplier: 3,
    maxDelay: 20,
    retryableStatusCodes: [502, 503]
)
```

### Backoff

The delay before retry *n* is `baseDelay × multiplier^(n−1)`, randomly changed by up to
``RetryPolicy/jitter`` in either direction, and never longer than ``RetryPolicy/maxDelay``.
The random part keeps thousands of devices from retrying at exactly the same moment after an
outage.

If the server sends `Retry-After`, in seconds or as an HTTP date, the client waits that long
instead. If the requested delay is longer than ``RetryPolicy/maxRetryAfter``, the client fails
right away rather than waiting.

### POST and PATCH aren't retried

`POST` and `PATCH` aren't idempotent: if a `POST` times out after the server has saved the data,
sending it again creates a duplicate. They are only retried when you opt in, for example when
your server deduplicates requests with an idempotency key:

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

### Cancellation stops retries

Cancelling a request during a backoff delay ends it immediately with
``NetworkError/cancelled``. No further attempts are sent.
