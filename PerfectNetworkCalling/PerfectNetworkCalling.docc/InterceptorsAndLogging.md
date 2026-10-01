# Interceptors and Logging

Change, observe and retry every request in one place.

## Overview

A ``NetworkInterceptor`` hooks into every attempt the client sends. Add interceptors to
``NetworkConfiguration/interceptors``. They run in the order you list them.

```swift
let client = NetworkClient(configuration: .init(
    baseURL: baseURL,
    interceptors: [
        AuthInterceptor(tokenProvider: session),   // adds the token first
        LoggingInterceptor(),                      // then logs the final request
    ]
))
```

### Hooks

For each attempt, including every retry, the client calls:

1. ``NetworkInterceptor/adapt(_:for:)``: change the request.
2. ``NetworkInterceptor/willSend(_:attempt:)``: the request is about to go out.
3. ``NetworkInterceptor/didReceive(_:data:for:duration:)``: an HTTP response arrived, with any status.
4. ``NetworkInterceptor/didFail(with:for:attempt:duration:)``: the attempt failed.
5. ``NetworkInterceptor/retryDecision(for:dueTo:attempt:)``: whether to try again.

Every hook has a default implementation, so you only write the ones you need.

### Writing an interceptor

```swift
struct HeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws -> URLRequest {
        var request = request
        request.setValue(Bundle.main.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "Accept-Language")
        return request
    }
}

struct AnalyticsInterceptor: NetworkInterceptor {
    func didFail(with error: NetworkError, for request: URLRequest, attempt: Int, duration: Duration) async {
        Analytics.track("network_error", ["path": request.url?.path ?? "", "error": "\(error)"])
    }
}
```

Interceptors must be `Sendable`, because many requests use them at the same time. Keep any
mutable state in an `actor`.

### Logging to the console

``LoggingInterceptor`` prints requests and responses to the Xcode console. It is enabled by
default in `DEBUG` builds. Here is the output for a `POST`:

```text
⬆️ POST https://api.example.com/users (attempt 1)
Headers:
  Accept: application/json
  Authorization: ***
  Content-Type: application/json
Body:
{
  "name" : "Ada"
}
cURL:
curl -X POST 'https://api.example.com/users' -H 'Accept: application/json' -H 'Authorization: ***' -H 'Content-Type: application/json' --data-raw '{"name":"Ada"}'

✅ 201 POST https://api.example.com/users (84 ms)
Headers:
  Content-Type: application/json
Body:
{
  "id" : 7,
  "name" : "Ada"
}
```

A failure looks like this:

```text
❌ 503 GET https://api.example.com/feed (1204 ms)
⛔️ GET https://api.example.com/feed failed (attempt 1, 1204 ms): The server ran into a problem (error 503). [HTTP 503]
```

Options:

| Option | Default | Meaning |
|---|---|---|
| ``LoggingInterceptor/level`` | `.body` | `.none`, `.basic` (one line each), `.headers`, `.body` |
| ``LoggingInterceptor/maxBodyLength`` | 4000 | Longer bodies are truncated. |
| ``LoggingInterceptor/redactedHeaders`` | `Authorization`, `Cookie`, `Set-Cookie`, `Proxy-Authorization` | Printed as `***`. |
| ``LoggingInterceptor/includesCURL`` | `true` | Print a cURL command at the `.body` level. |

Messages go to `os.Logger`, so you can filter them in Console.app by
``LoggingInterceptor/subsystem`` and ``LoggingInterceptor/category``. To send them somewhere
else, use the initializer that takes an `output` closure:

```swift
LoggingInterceptor(level: .basic) { message in print(message) }
```

> Important: Request and response bodies can contain personal data. Use `.basic` or `.none`
> in release builds.

### Authentication and token refresh

``AuthInterceptor`` adds `Authorization: Bearer <token>` to every request. When a request fails
with `401`, it refreshes the token through your ``AuthTokenProvider`` and retries the request
once:

```swift
actor SessionStore: AuthTokenProvider {
    private var accessToken: String?
    private var refreshToken: String?

    func token() async throws -> String? { accessToken }

    func refreshToken() async throws -> String {
        let response = try await authAPI.refresh(refreshToken)
        accessToken = response.accessToken
        return response.accessToken
    }
}

let client = NetworkClient(configuration: .init(
    baseURL: baseURL,
    interceptors: [AuthInterceptor(tokenProvider: sessionStore), LoggingInterceptor()]
))
```

If ten requests get `401` at the same moment, the token is refreshed **once**, and all ten
retry with the new token. See <doc:ConcurrencyAndReentrancy>.
