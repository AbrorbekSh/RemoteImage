import Foundation
import OSLog

actor Deduplicator<Key: Hashable & Sendable, Value: Sendable> {
    private var tasks: [Key: Task<Value, Error>] = [:]
    
    func run(key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let existing = tasks[key] {
            return try await withTaskCancellationHandler {
                try await existing.value
            } onCancel: {
                existing.cancel()
            }
        }
        
        let task = Task<Value, Error> {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        
        tasks[key] = task
        
        defer { tasks.removeValue(forKey: key) }
        
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
    
    func cancel(key: Key) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }
}

//actor Deduplicator<Key: Hashable & Sendable, Value: Sendable> {
//    private var tasks: [Key: Task<Value, Error>] = [:]
//    private let logger = Logger(subsystem: "ActorDeduplicator", category: "deduplication")
//
//    func run(
//        key: Key,
//        operation: @Sendable @escaping () async throws -> Value
//    ) async throws -> Value {
//        if let existing = tasks[key] {
//            logger.debug("🔄 Existing task for key: \(String(describing: key), privacy: .public)")
//            return try await existing.value
//        }
//
//        let task = Task {
//            defer { Task { self.removeTask(forKey: key) } }
//            logger.debug("▶️ Starting task for key: \(String(describing: key), privacy: .public)")
//            return try await operation()
//        }
//
//        tasks[key] = task
//
//        return try await withTaskCancellationHandler {
//            try await task.value
//        } onCancel: {
//            logger.debug("⚠️ Cancelled task for key: \(String(describing: key), privacy: .public)")
//            task.cancel()
//        }
//    }
//
//    private func removeTask(forKey key: Key) {
//        tasks.removeValue(forKey: key)
//    }
//}

//// MARK: - Deduplicator
//protocol Deduplicator: Sendable {
//    associatedtype Key: Hashable
//    associatedtype Value
//
//    func run(
//        key: Key,
//        operation: @Sendable @escaping () async throws -> Value
//    ) async throws -> Value
//}
//
//// MARK: - AnyDeduplicator
//struct AnyDeduplicator<Key: Hashable, Value: Sendable>: Deduplicator, @unchecked Sendable {
//    private let _run: @Sendable (Key, @Sendable @escaping () async throws -> Value) async throws -> Value
//
//    init<D: Deduplicator>(_ base: D) where D.Key == Key, D.Value == Value {
//        self._run = { key, op in try await base.run(key: key, operation: op) }
//    }
//
//    func run(
//        key: Key,
//        operation: @Sendable @escaping () async throws -> Value
//    ) async throws -> Value {
//        try await _run(key, operation)
//    }
//}
//
//// MARK: - InFlightDeduplicator (class-based)
//final class InFlightDeduplicator<Key: Hashable & Sendable, Value: Sendable>: Deduplicator, @unchecked Sendable {
//
//    private var tasks: [Key: Task<Value, Swift.Error>] = [:]
//    private let queue = DispatchQueue(label: "InFlightDeduplicator", attributes: .concurrent)
//    private let logger = Logger(subsystem: "InFlightDeduplicator", category: "InFlightDeduplicator")
//
//    func run(
//        key: Key,
//        operation: @Sendable @escaping () async throws -> Value
//    ) async throws -> Value {
//        // Read existing task safely
//        if let existing = syncReadTask(forKey: key) {
//            logger.debug("🔄 existing \(String(describing: key), privacy: .public)")
//            return try await existing.value
//        }
//
//        let task = Task {
//            defer { syncRemoveTask(forKey: key) }
//            logger.debug("▶️ start \(String(describing: key), privacy: .public)")
//            return try await operation()
//        }
//
//        syncWriteTask(task, forKey: key)
//
//        return try await withTaskCancellationHandler {
//            try await task.value
//        } onCancel: {
//            logger.debug("⚠️ handler cancel \(String(describing: key), privacy: .public)")
//            task.cancel()
//        }
//    }
//
//    // MARK: - Thread-safe access
//    private func syncReadTask(forKey key: Key) -> Task<Value, Error>? {
//        queue.sync { tasks[key] }
//    }
//
//    private func syncWriteTask(_ task: Task<Value, Error>, forKey key: Key) {
//        queue.async(flags: .barrier) {
//            self.tasks[key] = task
//        }
//    }
//
//    private func syncRemoveTask(forKey key: Key) {
//        queue.async(flags: .barrier) {
//            self.tasks.removeValue(forKey: key)
//        }
//    }
//}
