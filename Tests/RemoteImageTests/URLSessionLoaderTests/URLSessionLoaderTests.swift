import XCTest
@testable import RemoteImage
import OSLog

private class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

final class URLSessionLoaderTests: XCTestCase {
    
    private var session: URLSession!
    private var loader: URLSessionLoader!
    
    override func setUp() {
        super.setUp()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        loader = URLSessionLoader(session: session)
    }
    
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }
    
    func testConcurrentRequests() async throws {
        let url1 = URL(string: "https://example.com/image1.jpg")!
        let url2 = URL(string: "https://example.com/image2.jpg")!
        let data1 = Data(repeating: 1, count: 1024 * 1024)
        let data2 = Data(repeating: 2, count: 1024 * 1024)
        
        MockURLProtocol.requestHandler = { request in
            if request.url == url1 {
                return (HTTPURLResponse(url: url1, statusCode: 200, httpVersion: nil, headerFields: nil)!, data1)
            } else if request.url == url2 {
                return (HTTPURLResponse(url: url2, statusCode: 200, httpVersion: nil, headerFields: nil)!, data2)
            }
            throw URLError(.badURL)
        }
        
        let (receivedData1, _) = try await loader.data(for: url1, onProgress: { _, _ in })
        let (receivedData2, _) = try await loader.data(for: url2, onProgress: { _, _ in })
        
        XCTAssertEqual(receivedData1, data1)
        XCTAssertEqual(receivedData2, data2)
    }
    
    func testCancellation() async throws {
        let url = URL(string: "https://example.com/image.jpg")!
        let expectation = XCTestExpectation(description: "Request should be cancelled")
        
        MockURLProtocol.requestHandler = { request in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                XCTFail("Request should have been cancelled")
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let task = Task { [weak loader] in
            do {
                _ = try await loader?.data(for: url, onProgress: { _, _ in })
                XCTFail("Should have thrown cancellation error")
            } catch URLSessionLoader.LoaderError.cancelled {
                expectation.fulfill()
            } catch is CancellationError {
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        task.cancel()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testProgressUpdates() async throws {
        let url = URL(string: "https://example.com/image.jpg")!
        let data = Data(repeating: 1, count: 8192)
        var progressUpdates: [(Int64, Int64?)] = []
        
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        _ = try await loader.data(for: url, onProgress: { received, total in
            DispatchQueue.main.async {
                progressUpdates.append((received, total))
            }
        })
        
        XCTAssertEqual(progressUpdates.count, 2)
        XCTAssertEqual(progressUpdates[0].0, 4096)
        XCTAssertEqual(progressUpdates[1].0, 8192)
    }
    
    func testThreadSafety() async throws {
        let url = URL(string: "https://example.com/image.jpg")!
        let data = Data(repeating: 1, count: 1024 * 1024) // 1MB
        let concurrentCount = 100
        var tasks: [Task<Void, Error>] = []
        
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        for _ in 0..<concurrentCount {
            let task = Task { [weak loader] in
                _ = try await loader?.data(for: url, onProgress: { _, _ in })
            }
            tasks.append(task)
        }
        
        for task in tasks {
            _ = try await task.value
        }
    }
    
    func testInvalidStatus() async {
        let url = URL(string: "https://example.com/image.jpg")!
        
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        do {
            _ = try await loader.data(for: url, onProgress: { _, _ in })
            XCTFail("Should have thrown invalid status error")
        } catch URLSessionLoader.LoaderError.invalidStatus(let code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
