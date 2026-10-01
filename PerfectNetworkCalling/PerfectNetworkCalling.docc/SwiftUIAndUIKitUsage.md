# Using the Client in SwiftUI and UIKit

Call the client from a SwiftUI view model, or from UIKit code with completion handlers.

## Overview

### Sharing one client

Create the client once, and inject it where it's needed:

```swift
extension NetworkClient {
    static let api = NetworkClient(configuration: .init(
        baseURL: URL(string: "https://api.example.com/v1")!,
        interceptors: NetworkConfiguration.defaultInterceptors + [AuthInterceptor(tokenProvider: SessionStore.shared)]
    ))
}
```

### SwiftUI with an observable view model

```swift
@MainActor
@Observable
final class UserListModel {
    private let client: NetworkClient
    var users: [User] = []
    var errorMessage: String?
    var isLoading = false

    init(client: NetworkClient = .api) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await client.get("/users")
            errorMessage = nil
        } catch NetworkError.cancelled {
            // The view disappeared.
        } catch let error as NetworkError {
            errorMessage = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        } catch {}
    }
}

struct UserListView: View {
    @State private var model = UserListModel()

    var body: some View {
        List(model.users, id: \.id) { Text($0.name) }
            .overlay { if model.isLoading { ProgressView() } }
            .task { await model.load() }         // cancelled automatically on disappear
            .refreshable { await model.load() }
    }
}
```

The network call and the decoding run off the main actor. Only the assignment to `users`
happens on the main actor.

### UIKit with completion handlers

``NetworkClient/send(_:as:callbackQueue:completion:)`` calls a closure on the main queue
(by default), and returns a ``RequestToken`` that cancels the request:

```swift
final class ProfileViewController: UIViewController {
    private var loadToken: RequestToken?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadToken = NetworkClient.api.send(.get("/me"), as: Profile.self) { [weak self] result in
            switch result {
            case .success(let profile):
                self?.show(profile)
            case .failure(.cancelled):
                break
            case .failure(let error):
                self?.showAlert(title: error.errorDescription, message: error.recoverySuggestion)
            }
        }
    }

    deinit {
        loadToken?.cancel()
    }
}
```

### UIKit with async/await

```swift
private var loadTask: Task<Void, Never>?

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    loadTask = Task {
        do {
            let profile: Profile = try await NetworkClient.api.get("/me")
            show(profile)
        } catch {
            show(error)
        }
    }
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    loadTask?.cancel()
}
```

### Testing your code

Pass your own `URLSession` to ``NetworkClient/init(configuration:session:)`` with a custom
`URLProtocol` in `protocolClasses` to return canned responses in unit tests, without touching
the network.
