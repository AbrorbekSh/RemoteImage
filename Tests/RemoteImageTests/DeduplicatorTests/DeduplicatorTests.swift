import XCTest
@testable import RemoteImage

final class DeduplicatorTests: XCTestCase {
    enum TestError: Error {
        case simulatedError
    }
    
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            _value += 1
        }
    }

    func testSameKeyOnlyRunsOnce() async throws {
        let deduplicator = Deduplicator<String, Int>()
        let counter = Counter()

        let operation: @Sendable () async throws -> Int = {
            try await Task.sleep(nanoseconds: 100_000_000)
            counter.increment()
            return counter.value
        }

        async let result1 = deduplicator.run(key: "test", operation: operation)
        async let result2 = deduplicator.run(key: "test", operation: operation)

        let (value1, value2) = try await (result1, result2)

        XCTAssertEqual(value1, 1)
        XCTAssertEqual(value2, 1)
        XCTAssertEqual(counter.value, 1)
    }
    
    func testDifferentKeysRunSeparately() async throws {
        let deduplicator = Deduplicator<String, Int>()
        let counter = Counter()
        
        let operation: @Sendable () async throws -> Int = {
            counter.increment()
            return counter.value
        }
        
        let result1 = try await deduplicator.run(key: "test1", operation: operation)
        let result2 = try await deduplicator.run(key: "test2", operation: operation)
        
        XCTAssertEqual(result1, 1)
        XCTAssertEqual(result2, 2)
        XCTAssertEqual(counter.value, 2)
    }
    
    func testTaskRemovedAfterCompletion() async throws {
        let deduplicator = Deduplicator<String, Int>()
        let counter = Counter()
        
        let operation: @Sendable () async throws -> Int = {
            counter.increment()
            return counter.value
        }
        
        _ = try await deduplicator.run(key: "test", operation: operation)
        _ = try await deduplicator.run(key: "test", operation: operation)
        
        XCTAssertEqual(counter.value, 2)
    }
    
    func testErrorPropagation() async {
        let deduplicator = Deduplicator<String, Int>()
        
        let failingOperation: @Sendable () async throws -> Int = {
            throw TestError.simulatedError
        }
        
        do {
            _ = try await deduplicator.run(key: "test", operation: failingOperation)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? TestError, TestError.simulatedError)
        }
    }
    
    func testCancellation() async {
        let deduplicator = Deduplicator<String, Int>()
        let counter = Counter()
        
        let operation: @Sendable () async throws -> Int = {
            counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000)
            return 42
        }
        
        let task = Task {
            try await deduplicator.run(key: "test", operation: operation)
        }
        
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        XCTAssertEqual(counter.value, 1)
    }
}
