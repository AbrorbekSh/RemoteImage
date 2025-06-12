import XCTest
@testable import RemoteImage
import UIKit

final class MemoryImageCacheTests: XCTestCase {
    var cache: MemoryImageCache!
    let url = URL(string: "https://example.com/image.png")!
    let image = UIImage()

    override func setUp() {
        super.setUp()
        cache = MemoryImageCache()
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    func test_insertImage_storesImage() {
        cache.insert(image, for: url)
        XCTAssertEqual(cache.image(for: url), image)
    }

    func test_imageNotInserted_returnsNil() {
        XCTAssertNil(cache.image(for: url))
    }

    func test_removeImage_deletesFromCache() {
        cache.insert(image, for: url)
        cache.remove(for: url)
        XCTAssertNil(cache.image(for: url))
    }

    func test_clearCache_removesAllImages() {
        let url2 = URL(string: "https://example.com/another.png")!
        cache.insert(image, for: url)
        cache.insert(image, for: url2)
        cache.clearCache()
        XCTAssertNil(cache.image(for: url))
        XCTAssertNil(cache.image(for: url2))
    }
}
