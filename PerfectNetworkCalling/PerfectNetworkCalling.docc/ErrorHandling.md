# Error Handling

Show helpful messages and react to specific failures.

## Overview

Every method of ``NetworkClient`` throws ``NetworkError`` and nothing else. Each error has:

- ``NetworkError/errorDescription``: a short message you can show to users.
- ``NetworkError/recoverySuggestion``: what the user can do next.
- ``NetworkError/failureReason``: technical details for your logs.

### Showing errors

```swift
do {
    try await viewModel.save()
} catch let error as NetworkError {
    alert = Alert(title: error.errorDescription ?? "Error", message: error.recoverySuggestion ?? "")
}
```

For `4xx` responses, the server's own message is used when it sends one. The client looks for
the JSON fields `message`, `error_description`, `detail`, `error` and `title`, including inside
a nested `error` object or an `errors` array. `5xx` messages are never shown to users, because
they are often technical.

### Reacting to specific errors

```swift
do {
    profile = try await client.get("/me")
} catch NetworkError.unauthorized {
    session.signOut()
} catch NetworkError.cancelled {
    // The user navigated away. Nothing to show.
} catch NetworkError.noInternetConnection {
    showOfflineBanner()
} catch let error as NetworkError where error.statusCode == 402 {
    showPaywall()
} catch {
    show(error)
}
```

### Error cases

| Case | When it happens |
|---|---|
| ``NetworkError/invalidURL(_:)`` | The URL couldn't be built. |
| ``NetworkError/encodingFailed(_:)`` | The request body couldn't be encoded. |
| ``NetworkError/noInternetConnection`` | The device is offline. |
| ``NetworkError/connectionLost`` | The connection dropped mid-request. |
| ``NetworkError/cannotConnectToHost`` | DNS failed or the server refused the connection. |
| ``NetworkError/sslError`` | The TLS handshake or certificate check failed. |
| ``NetworkError/timedOut`` | The request took longer than its timeout. |
| ``NetworkError/cancelled`` | The request was cancelled. |
| ``NetworkError/badRequest(_:)`` | `400` |
| ``NetworkError/unauthorized(_:)`` | `401` |
| ``NetworkError/forbidden(_:)`` | `403` |
| ``NetworkError/notFound(_:)`` | `404` |
| ``NetworkError/conflict(_:)`` | `409` |
| ``NetworkError/unprocessableEntity(_:)`` | `422` |
| ``NetworkError/rateLimited(_:)`` | `429` |
| ``NetworkError/clientError(_:)`` | Any other `4xx` |
| ``NetworkError/serverError(_:)`` | Any `5xx` |
| ``NetworkError/unexpectedStatus(_:)`` | Any other non-`2xx` status |
| ``NetworkError/invalidResponse`` | The response wasn't HTTP. |
| ``NetworkError/decodingFailed(_:)`` | The body didn't match the requested type. |
| ``NetworkError/unknown(_:)`` | Anything else. |

### Reading the server's error body

HTTP-status cases carry an ``HTTPErrorResponse`` with the status code, headers and raw body.
Decode it into your own error model:

```swift
struct ValidationErrors: Decodable { let fields: [String: String] }

do {
    let _: User = try await client.post("/users", body: form)
} catch let NetworkError.unprocessableEntity(response) {
    let errors = try? response.decode(ValidationErrors.self)
    highlight(errors?.fields ?? [:])
}
```

### Debugging decoding failures

``NetworkError/decodingFailed(_:)`` says exactly which field failed, for example
`Missing key 'name' at user.name.` or `Type mismatch at items[2].price: expected Double.`
``LoggingInterceptor`` prints this detail in the console next to the response body.
