# Making Requests

Send GET, POST, PUT, PATCH and DELETE requests with query parameters, headers and bodies.

## Overview

There are two ways to send a request:

- **Verb methods** such as ``NetworkClient/get(_:query:headers:timeout:retry:as:)`` are the
  shortest way for everyday calls.
- An ``Endpoint`` passed to ``NetworkClient/request(_:as:)`` gives you every option, and can be
  stored, reused and sent in batches.

### Verb methods

```swift
let user: User = try await client.get("/users/1", query: ["expand": "profile"])

let created: User = try await client.post("/users", body: NewUser(name: "Ada"))

let replaced: User = try await client.put("/users/1", body: user)

let patched: User = try await client.patch("/users/1", body: ["name": "Ada Lovelace"])

let _: EmptyResponse = try await client.delete("/users/1")
```

Every verb method also accepts `headers`, `timeout` and `retry`:

```swift
let report: Report = try await client.get(
    "/reports/annual",
    headers: ["Accept-Language": "en"],
    timeout: 60,
    retry: .aggressive
)
```

### Endpoints

An ``Endpoint`` describes a request as a value. Build it with a factory method or the
initializer:

```swift
let search = Endpoint.get("/search", query: ["q": "swift"], timeout: 5)

let upload = Endpoint(
    path: "/avatars",
    method: .put,
    body: .data(pngData, contentType: "image/png"),
    timeout: 120
)

let login = Endpoint(
    path: "/oauth/token",
    method: .post,
    body: .formURLEncoded(["grant_type": "password", "username": email, "password": password])
)

let results = try await client.request(search, as: [Repo].self)
```

A good way to organize an API is to group its endpoints in an extension:

```swift
extension Endpoint {
    static func user(_ id: Int) -> Endpoint { .get("/users/\(id)") }
    static func updateUser(_ user: User) -> Endpoint { .put("/users/\(user.id)", body: user) }
}

let user: User = try await client.request(.user(42))
```

### Paths and URLs

``Endpoint/path`` is appended to ``NetworkConfiguration/baseURL``. A leading `/` is optional.
If the path is a full URL, such as a pre-signed download link, the base URL is ignored.

Query parameters are sorted by key, and a `+` in a value is sent as `%2B`, so servers don't
read it as a space.

### Headers

The final headers are built in this order, with later ones winning:

1. `Accept: application/json`
2. ``NetworkConfiguration/defaultHeaders``
3. ``Endpoint/headers``
4. Changes made by interceptors, such as `Authorization` from ``AuthInterceptor``.

A `Content-Type` that matches the body is added unless you set one yourself.

### Response types

| Type you ask for | What the client does |
|---|---|
| Any `Decodable & Sendable` type | Decodes the JSON body with ``NetworkConfiguration/decoder``. |
| ``EmptyResponse`` | Ignores the body. Use it for `204 No Content`. |
| `Data` | Returns the raw body. |

Use ``NetworkClient/requestData(_:)`` when you also need the `HTTPURLResponse`, for
example to read response headers.

### Custom date and key strategies

Configure the encoder and decoder once on the configuration:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601

let client = NetworkClient(configuration: .init(baseURL: baseURL, decoder: decoder))
```
