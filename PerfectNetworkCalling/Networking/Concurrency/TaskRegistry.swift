//
//  TaskRegistry.swift
//  PerfectNetworkCalling
//

import Foundation

/// Keeps track of in-flight requests so they can be cancelled from anywhere.
///
/// Every method is synchronous (no `await` inside), so each one runs from start to finish
/// without another call interleaving. This avoids actor reentrancy problems: a request can't
/// finish halfway through ``cancelAll()``, and a key can't end up pointing at a request that
/// has already been removed.
actor TaskRegistry {
    private var cancellers: [UUID: @Sendable () -> Void] = [:]
    private var keys: [String: UUID] = [:]

    /// The number of requests being tracked.
    var count: Int { cancellers.count }

    /// Starts tracking a request. If `key` is already used by another request, that request is cancelled.
    func register(_ id: UUID, key: String?, cancel: @escaping @Sendable () -> Void) {
        if let key {
            if let previous = keys[key], let cancelPrevious = cancellers.removeValue(forKey: previous) {
                cancelPrevious()
            }
            keys[key] = id
        }
        cancellers[id] = cancel
    }

    /// Stops tracking a finished request.
    func remove(_ id: UUID, key: String?) {
        cancellers[id] = nil
        if let key, keys[key] == id {
            keys[key] = nil
        }
    }

    /// Cancels the in-flight request with the given key.
    func cancel(key: String) {
        guard let id = keys.removeValue(forKey: key) else { return }
        cancellers.removeValue(forKey: id)?()
    }

    /// Cancels every in-flight request.
    func cancelAll() {
        let all = Array(cancellers.values)
        cancellers.removeAll()
        keys.removeAll()
        all.forEach { $0() }
    }
}
