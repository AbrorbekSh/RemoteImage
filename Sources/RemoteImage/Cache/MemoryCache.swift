import UIKit
import OSLog

final class MemoryImageCache: @unchecked Sendable, ImageCache {
    private static let logger = Logger(subsystem: "zimran.imagecache",
                                       category: "memory")

    private let storage: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 150
        c.totalCostLimit = 300 * 1024 * 1024 /// 300 MB
        return c
    }()

    init(countLimit: Int = 500) {
        storage.countLimit = countLimit
        Self.logger.debug("Initialized MemoryImageCache with count limit: \(countLimit)")
    }

    // MARK: ImageCache

    func image(for key: URL) -> UIImage? {
        let result = storage.object(forKey: key as NSURL)
        if result != nil {
            Self.logger.debug("Cache hit for key: \(key.absoluteString, privacy: .public)")
        } else {
            Self.logger.debug("Cache miss for key: \(key.absoluteString, privacy: .public)")
        }
        return result
    }

    func insert(_ image: UIImage, for key: URL) {
        storage.setObject(image, forKey: key as NSURL)
        Self.logger.debug("Inserted image into memory cache for key: \(key.absoluteString, privacy: .public)")
    }

    func remove(for key: URL) {
        storage.removeObject(forKey: key as NSURL)
        Self.logger.debug("Removed image from memory cache for key: \(key.absoluteString, privacy: .public)")
    }

    func clearCache() {
        storage.removeAllObjects()
        Self.logger.debug("Cleared memory image cache")
    }
}
