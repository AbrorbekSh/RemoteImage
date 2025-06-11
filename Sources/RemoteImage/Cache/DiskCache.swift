import UIKit
import OSLog

final class DiskImageCache: @unchecked Sendable, ImageCache {
    private static let logger = Logger(subsystem: "zimran.imagecache", category: "disk")

    private let root: URL
    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "zimran.imagecache.disk.queue", attributes: .concurrent)

    init(
        directory: URL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageCache", isDirectory: true)
    ) throws {
        root = directory
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Failed to create cache directory: \(error.localizedDescription)")
            throw ImageCacheError.fileSystem(error)
        }
    }

    // MARK: - ImageCache

    func image(for key: URL) throws -> UIImage? {
        let path = self.path(for: key)
        return try queue.sync {
            do {
                let data = try Data(contentsOf: path)
                guard let image = UIImage(data: data) else {
                    Self.logger.warning("Data at \(path) is not a valid image")
                    return nil
                }
                return image
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                Self.logger.warning("File not found at \(path)")
                return nil
            } catch {
                Self.logger.error("Read failed for \(path): \(error.localizedDescription)")
                throw ImageCacheError.fileSystem(error)
            }
        }
    }

    func insert(_ image: UIImage, for key: URL) throws {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            Self.logger.error("Unable to encode image for \(key.absoluteString)")
            throw ImageCacheError.imageEncodingFailed
        }

        let path = self.path(for: key)
        try queue.sync(flags: .barrier) {
            do {
                try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                Self.logger.error("Write failed for \(path): \(error.localizedDescription)")
                throw ImageCacheError.fileSystem(error)
            }
        }
    }

    func remove(for key: URL) throws {
        let path = self.path(for: key)
        try queue.sync(flags: .barrier) {
            guard fm.fileExists(atPath: path.path) else { return }
            do {
                try fm.removeItem(at: path)
            } catch {
                Self.logger.error("Remove failed for \(path): \(error.localizedDescription)")
                throw ImageCacheError.fileSystem(error)
            }
        }
    }

    func clearCache() throws {
        try queue.sync(flags: .barrier) {
            do {
                let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for url in contents {
                    do {
                        try fm.removeItem(at: url)
                        print("Deleted: \(url.lastPathComponent)")
                    } catch {
                        Self.logger.error("Failed to delete \(url): \(error.localizedDescription)")
                    }
                }
            } catch {
                Self.logger.error("Bulk clear failed: \(error.localizedDescription)")
                throw ImageCacheError.fileSystem(error)
            }
        }
    }

    // MARK: - Helpers

    private func path(for key: URL) -> URL {
        root.appendingPathComponent(key.absoluteString.sha256).appendingPathExtension("cache")
    }
}
