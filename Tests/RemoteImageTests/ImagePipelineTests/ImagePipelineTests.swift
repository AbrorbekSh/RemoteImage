import XCTest
@testable import RemoteImage

private final class MockDataLoader: DataLoader, @unchecked Sendable {
    var dataToReturn: Data = Data()
    var responseToReturn: URLResponse = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                                         statusCode: 200,
                                                         httpVersion: nil,
                                                         headerFields: nil)!
    var capturedProgress: [(Int64, Int64)] = []

    func data(for url: URL, onProgress progress: @escaping (Int64, Int64?) -> Void) async throws -> (Data, URLResponse) {
        capturedProgress.append((50, 100))
        progress(50, 100)
        return (dataToReturn, responseToReturn)
    }
}

private final class MockImageCache: ImageCache, @unchecked Sendable {
    func remove(for key: URL) async throws {}
    
    func clearCache() async throws {}
    
    var storedImages: [URL: UIImage] = [:]
    var imageToReturn: UIImage? = nil

    func image(for url: URL) async throws -> UIImage? {
        return imageToReturn
    }

    func insert(_ image: UIImage, for url: URL) async throws {
        storedImages[url] = image
    }
}

private final class SlowMockDataLoader: DataLoader {
    func data(for url: URL, onProgress progress: @escaping (Int64, Int64?) -> Void) async throws -> (Data, URLResponse) {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class ImagePipelineTests: XCTestCase {

    func testImageFromCache() async throws {
        let mockCache = MockImageCache()
        let mockImage = UIImage(systemName: "checkmark")!
        mockCache.imageToReturn = mockImage

        let pipeline = ImagePipeline(
            loader: MockDataLoader(),
            cache: mockCache
        )

        let image = try await pipeline.image(from: URL(string: "https://test.com/image.png")!) { _ in }
        XCTAssertEqual(image, mockImage)
    }

    func testImageDownloadSuccess() async throws {
        let mockLoader = MockDataLoader()
        let mockCache = MockImageCache()
        let imageData = UIImage(systemName: "checkmark")!.pngData()!
        mockLoader.dataToReturn = imageData

        let pipeline = ImagePipeline(
            loader: mockLoader,
            cache: mockCache
        )

        let url = URL(string: "https://test.com/image.png")!
        let image = try await pipeline.image(from: url) { progress in
            XCTAssertEqual(progress, 0.5)
        }

        XCTAssertNotNil(image)
        XCTAssertEqual(mockCache.storedImages[url], image)
    }

    func testBadHTTPStatusThrowsError() async {
        let mockLoader = MockDataLoader()
        mockLoader.responseToReturn = HTTPURLResponse(url: URL(string: "https://fail.com")!,
                                                      statusCode: 404,
                                                      httpVersion: nil,
                                                      headerFields: nil)!
        let pipeline = ImagePipeline(
            loader: mockLoader,
            cache: MockImageCache()
        )

        do {
            _ = try await pipeline.image(from: URL(string: "https://fail.com")!) { _ in }
            XCTFail("Expected error to be thrown")
        } catch let error as ImagePipeline.PipelineError {
            if case .badHTTPStatus(let code) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Unexpected PipelineError case")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func testInvalidImageDataThrowsError() async {
        let mockLoader = MockDataLoader()
        mockLoader.dataToReturn = Data("not an image".utf8)

        let pipeline = ImagePipeline(
            loader: mockLoader,
            cache: MockImageCache()
        )

        do {
            _ = try await pipeline.image(from: URL(string: "https://badimage.com")!) { _ in }
            XCTFail("Expected decodingFailed error")
        } catch let error as ImagePipeline.PipelineError {
            XCTAssertEqual(error, .decodingFailed)
        } catch {
            XCTFail("Unexpected error")
        }
    }
    
    func testImageDownloadCancellation() async {
        let expectation = XCTestExpectation(description: "Cancellation expectation")

        let slowLoader = SlowMockDataLoader()
        let pipeline = ImagePipeline(
            loader: slowLoader,
            cache: MockImageCache()
        )

        let url = URL(string: "https://cancel.com")!
        let task = Task {
            do {
                _ = try await pipeline.image(from: url) { _ in }
                XCTFail("Expected task to be cancelled")
            } catch is CancellationError {
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            task.cancel()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }

}

extension ImagePipeline.PipelineError: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.badHTTPStatus(let l), .badHTTPStatus(let r)):
            return l == r
        case (.decodingFailed, .decodingFailed):
            return true
        case (.underlying, .underlying):
            return true
        default:
            return false
        }
    }
}
