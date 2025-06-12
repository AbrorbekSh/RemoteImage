import UIKit
import CryptoKit
import OSLog

// MARK: - Protocol

protocol ImageCache: Sendable {
    func image(for key: URL) async throws -> UIImage?
    func insert(_ image: UIImage, for key: URL) async throws
    func remove(for key: URL) async throws
    func clearCache() async throws
}

// MARK: - TieredImageCache

public final class TieredImageCache: ImageCache {
    private static let logger = Logger(subsystem: "zimran.imagecache",
                                       category: "tiered")

    private let primary: ImageCache
    private let secondary: ImageCache

    public static let shared = TieredImageCache()

    init(
        primary: ImageCache = MemoryImageCache(),
        secondary: ImageCache = try! DiskImageCache()
    ) {
        self.primary = primary
        self.secondary = secondary
    }

    func image(for key: URL) async throws -> UIImage? {
        Self.logger.debug("Attempting to retrieve image for key: \(key.absoluteString, privacy: .public)")

        if let img = try await primary.image(for: key) {
            Self.logger.debug("Image found in primary cache for key: \(key.absoluteString, privacy: .public)")
            return img
        }

        if let img = try await secondary.image(for: key) {
            Self.logger.debug("Image found in secondary cache for key: \(key.absoluteString, privacy: .public)")
            Task {
                do {
                    try await primary.insert(img, for: key)
                    Self.logger.debug("Promoted image to primary cache for key: \(key.absoluteString, privacy: .public)")
                } catch {
                    Self.logger.error("Failed to promote image to primary cache for key: \(key.absoluteString, privacy: .public), error: \(String(describing: error), privacy: .public)")
                }
            }
            return img
        }

        Self.logger.debug("Image not found in any cache for key: \(key.absoluteString, privacy: .public)")
        return nil
    }

    func insert(_ image: UIImage, for key: URL) async throws {
        Self.logger.debug("Inserting image for key: \(key.absoluteString, privacy: .public)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.insert(image, for: key) }
            group.addTask { try await self.secondary.insert(image, for: key) }
            try await group.waitForAll()
        }
        Self.logger.debug("Successfully inserted image for key: \(key.absoluteString, privacy: .public)")
    }

    func remove(for key: URL) async throws {
        Self.logger.debug("Removing image for key: \(key.absoluteString, privacy: .public)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.remove(for: key) }
            group.addTask { try await self.secondary.remove(for: key) }
            try await group.waitForAll()
        }
        Self.logger.debug("Successfully removed image for key: \(key.absoluteString, privacy: .public)")
    }

    public func clearCache() async throws {
        Self.logger.debug("Clearing all caches")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.clearCache() }
            group.addTask { try await self.secondary.clearCache() }
            try await group.waitForAll()
        }
        Self.logger.debug("Successfully cleared all caches")
    }
}

// MARK: - SHA-256 helper

extension String {
    var sha256: String {
        SHA256.hash(data: Data(utf8))
              .map { String(format: "%02x", $0) }
              .joined()
    }
}

// MARK: Error

enum ImageCacheError: Error, Equatable {
    case imageEncodingFailed
    case imageDataCorrupted
    case fileSystem(Error)

    static func == (lhs: ImageCacheError, rhs: ImageCacheError) -> Bool {
        switch (lhs, rhs) {
        case (.imageEncodingFailed, .imageEncodingFailed),
             (.imageDataCorrupted, .imageDataCorrupted):
            return true
        case (.fileSystem, .fileSystem):
            return true
        default:
            return false
        }
    }
}
