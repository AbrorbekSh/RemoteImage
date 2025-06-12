import Foundation
import OSLog

actor Deduplicator<Key: Hashable & Sendable, Value: Sendable> {
    private var tasks: [Key: Task<Value, Error>] = [:]
    private let logger = Logger(subsystem: "ActorDeduplicator", category: "deduplication")

    func run(
        key: Key,
        operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        if let existing = tasks[key] {
            logger.debug("🔄 Existing task for key: \(String(describing: key), privacy: .public)")
            return try await existing.value
        }

        let task = Task {
            defer { Task { self.removeTask(forKey: key) } }
            logger.debug("▶️ Starting task for key: \(String(describing: key), privacy: .public)")
            return try await operation()
        }

        tasks[key] = task

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            logger.debug("⚠️ Cancelled task for key: \(String(describing: key), privacy: .public)")
            task.cancel()
        }
    }

    private func removeTask(forKey key: Key) {
        tasks.removeValue(forKey: key)
    }
}
