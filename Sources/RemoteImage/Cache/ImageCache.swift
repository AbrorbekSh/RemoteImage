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
        if let img = try await primary.image(for: key) { return img }

        if let img = try await secondary.image(for: key) {
            Task { try? await primary.insert(img, for: key) }
            return img
        }
        return nil
        
    }

    func insert(_ image: UIImage, for key: URL) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.insert(image, for: key) }
            group.addTask { try await self.secondary.insert(image, for: key) }
            try await group.waitForAll()
        }
    }

    func remove(for key: URL) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.remove(for: key) }
            group.addTask { try await self.secondary.remove(for: key) }
            try await group.waitForAll()
        }
    }

    public func clearCache() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.primary.clearCache() }
            group.addTask { try await self.secondary.clearCache() }
            try await group.waitForAll()
        }
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

enum ImageCacheError: Error {
    case imageEncodingFailed
    case imageDataCorrupted
    case fileSystem(Error)
}
