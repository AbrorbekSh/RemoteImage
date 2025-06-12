import XCTest
@testable import RemoteImage
import UIKit

final class DiskImageCacheTests: XCTestCase {
    var cache: DiskImageCache!
    var tempDirectory: URL!
    let testURL = URL(string: "https://example.com/image.png")!
    let image = UIImage(systemName: "checkmark.circle")!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        cache = try DiskImageCache(directory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        cache = nil
        tempDirectory = nil
    }

    func test_insertImage_savesToDisk() throws {
        try cache.insert(image, for: testURL)

        let loaded = try cache.image(for: testURL)
        XCTAssertNotNil(loaded)
    }

    func test_imageNotInserted_returnsNil() throws {
        let result = try cache.image(for: testURL)
        XCTAssertNil(result)
    }

    func test_removeImage_deletesFile() throws {
        try cache.insert(image, for: testURL)
        try cache.remove(for: testURL)

        let result = try cache.image(for: testURL)
        XCTAssertNil(result)
    }

    func test_clearCache_deletesAllFiles() throws {
        let anotherURL = URL(string: "https://example.com/2.png")!
        try cache.insert(image, for: testURL)
        try cache.insert(image, for: anotherURL)

        try cache.clearCache()

        XCTAssertNil(try cache.image(for: testURL))
        XCTAssertNil(try cache.image(for: anotherURL))
    }

    func test_insertInvalidImage_throws() throws {
        let invalidImage = UIImage() 
        let badCache = try DiskImageCache(directory: tempDirectory)

        XCTAssertThrowsError(try badCache.insert(invalidImage, for: testURL)) { error in
            XCTAssertEqual(error as? ImageCacheError, .imageEncodingFailed)
        }
    }
}
