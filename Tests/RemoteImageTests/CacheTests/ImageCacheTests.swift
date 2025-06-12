import XCTest
@testable import RemoteImage
import UIKit


private final class MockImageCache: @unchecked Sendable, ImageCache {
    var images: [URL: UIImage] = [:]
    var inserted: [(UIImage, URL)] = []
    var removed: [URL] = []
    var cleared = false

    func image(for key: URL) async throws -> UIImage? {
        return images[key]
    }

    func insert(_ image: UIImage, for key: URL) async throws {
        inserted.append((image, key))
        images[key] = image
    }

    func remove(for key: URL) async throws {
        removed.append(key)
        images.removeValue(forKey: key)
    }

    func clearCache() async throws {
        cleared = true
        images.removeAll()
    }
}

final class TieredImageCacheTests: XCTestCase {
    private var primary: MockImageCache!
    private var secondary: MockImageCache!
    private var cache: TieredImageCache!

    override func setUp() {
        super.setUp()
        primary = MockImageCache()
        secondary = MockImageCache()
        cache = TieredImageCache(primary: primary, secondary: secondary)
    }
    
    override func tearDown() {
        primary = nil
        secondary = nil
        cache = nil
        super.tearDown()
    }

    func test_imageFoundInPrimary_returnsImmediately() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let image = UIImage()
        primary.images[url] = image

        let result = try await cache.image(for: url)

        XCTAssertEqual(result, image)
    }

    func test_imageFoundInSecondary_insertsIntoPrimary() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let image = UIImage()
        secondary.images[url] = image

        let result = try await cache.image(for: url)

        XCTAssertEqual(result, image)
        try await Task.sleep(nanoseconds: 100_000_000) 
        XCTAssertEqual(primary.images[url], image)
    }

    func test_imageNotFound_returnsNil() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let result = try await cache.image(for: url)
        XCTAssertNil(result)
    }

    func test_insert_insertsIntoBothCaches() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let image = UIImage()

        try await cache.insert(image, for: url)

        XCTAssertEqual(primary.images[url], image)
        XCTAssertEqual(secondary.images[url], image)
    }

    func test_remove_removesFromBothCaches() async throws {
        let url = URL(string: "https://example.com/image.png")!
        primary.images[url] = UIImage()
        secondary.images[url] = UIImage()

        try await cache.remove(for: url)

        XCTAssertNil(primary.images[url])
        XCTAssertNil(secondary.images[url])
    }

    func test_clearCache_clearsBothCaches() async throws {
        primary.images[URL(string: "https://a.com")!] = UIImage()
        secondary.images[URL(string: "https://b.com")!] = UIImage()

        try await cache.clearCache()

        XCTAssertTrue(primary.cleared)
        XCTAssertTrue(secondary.cleared)
    }
}
