//
//  RequestDeduplicator.swift
//  PerfectNetworkCalling
//

import Foundation

/// Lets identical in-flight requests share one network call.
///
/// Each caller waits on its own continuation, so one caller can cancel without affecting the
/// others. The shared call is cancelled only when every caller has cancelled.
///
/// Reentrancy: the continuation is registered in the same synchronous step that checks for
/// cancellation, and each entry has its own ID, so a call that finishes late can never remove a
/// newer entry for the same key.
actor RequestDeduplicator {
    typealias Output = (Data, HTTPURLResponse)

    private struct Entry {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Output, any Error>]
    }

    private var entries: [String: Entry] = [:]

    /// Runs `operation`, or joins an identical one that is already running.
    func run(key: String, operation: @escaping @Sendable () async throws -> Output) async throws -> Output {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                join(key: key, waiterID: waiterID, continuation: continuation, operation: operation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, key: key) }
        }
    }

    private func join(
        key: String,
        waiterID: UUID,
        continuation: CheckedContinuation<Output, any Error>,
        operation: @escaping @Sendable () async throws -> Output
    ) {
        if Task.isCancelled {
            continuation.resume(throwing: NetworkError.cancelled)
            return
        }
        if entries[key] != nil {
            entries[key]?.waiters[waiterID] = continuation
            return
        }
        let entryID = UUID()
        let task = Task {
            let result: Result<Output, any Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            self.finish(entryID, key: key, result: result)
        }
        entries[key] = Entry(id: entryID, task: task, waiters: [waiterID: continuation])
    }

    private func finish(_ entryID: UUID, key: String, result: Result<Output, any Error>) {
        guard let entry = entries[key], entry.id == entryID else { return }
        entries[key] = nil
        for continuation in entry.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func cancelWaiter(_ waiterID: UUID, key: String) {
        guard var entry = entries[key], let continuation = entry.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: NetworkError.cancelled)
        if entry.waiters.isEmpty {
            entry.task.cancel()
            entries[key] = nil
        } else {
            entries[key] = entry
        }
    }
}
