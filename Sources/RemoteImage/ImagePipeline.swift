import UIKit
import OSLog

// MARK: - Typealiases
public typealias DataResponse = (data: Data, response: URLResponse)
public typealias ProgressHandler = @Sendable (Double) -> Void

// MARK: - Image Pipeline Protocol
public protocol ImagePipelineProtocol: Sendable {
    func image(from url: URL, progress: @escaping ProgressHandler) async throws -> UIImage
}

// MARK: - Image Pipeline
public final class ImagePipeline: ImagePipelineProtocol {

    // MARK: Logging
    private static let log = Logger(subsystem: "zimran.ImagePipeline", category: "pipeline")

    // MARK: Singleton
    public static let shared = ImagePipeline()

    // MARK: Dependencies
    private let loader: DataLoader
    private let cache: ImageCache
    private let dedup: Deduplicator<URL, DataResponse>

    // MARK: Initialization
    init(
        loader: DataLoader = URLSessionLoader(),
        cache: ImageCache = TieredImageCache.shared,
        deduplicator: Deduplicator<URL, DataResponse> = Deduplicator<URL, DataResponse>()
    ) {
        self.loader = loader
        self.cache = cache
        self.dedup = deduplicator
        Self.log.debug("ImagePipeline initialised")
    }

    // MARK: Public API
    public func image(from url: URL, progress: @escaping ProgressHandler) async throws -> UIImage {
        do {
            let image = try await load(from: url, progress: progress)
            Self.log.info("✅ Finished \(url, privacy: .public) size=\(image.size.debugDescription, privacy: .public)")
            return image
        } catch is CancellationError {
            Self.log.notice("Download cancelled \(url, privacy: .public)")
            throw CancellationError()
        } catch {
            Self.log.error("❌ Failed \(url, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: Errors
    enum PipelineError: Error {
        case badHTTPStatus(Int)
        case decodingFailed
        case underlying(Error)
    }

    // MARK: Private Helpers
    private func load(from url: URL, progress: ProgressHandler?) async throws -> UIImage {
        if let cached = try await cache.image(for: url) {
            Self.log.debug("Cache-hit \(url, privacy: .public)")
            return cached
        }

        Self.log.debug("Cache-miss \(url, privacy: .public)")

        let (data, response): DataResponse = try await dedup.run(key: url) {
            try await self.loader.data(for: url) { received, total in
                guard let total, let progress, !Task.isCancelled else { return }
                let fraction = Double(received) / Double(total)
                progress(fraction)
            }
        }

        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw PipelineError.badHTTPStatus(http.statusCode)
        }

        guard let image = UIImage(data: data) else {
            throw PipelineError.decodingFailed
        }

        try await cache.insert(image, for: url)
        return image
    }
}
