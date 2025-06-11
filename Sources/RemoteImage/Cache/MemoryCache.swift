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

    init(countLimit: Int = 500) { storage.countLimit = countLimit }

    // MARK: ImageCache

    func image(for key: URL) -> UIImage? {
        storage.object(forKey: key as NSURL)
    }

    func insert(_ image: UIImage, for key: URL) {
        storage.setObject(image, forKey: key as NSURL)
    }

    func remove(for key: URL) {
        storage.removeObject(forKey: key as NSURL)
    }

    func clearCache() {
        storage.removeAllObjects()
    }
}
