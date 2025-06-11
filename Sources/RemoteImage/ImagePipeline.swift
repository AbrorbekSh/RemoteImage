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
    private static let log = Logger(subsystem: "zimran.ImagePipeline",
                                         category: "pipeline")

    // MARK: Singleton
    public static let shared = ImagePipeline()

    // MARK: Dependencies
    private let loader: DataLoader
    private let cache:  ImageCache
    private let dedup:  Deduplicator<URL, DataResponse>

    // MARK: Initialization
    init(
        loader: DataLoader = URLSessionLoader(),
        cache:  ImageCache  = TieredImageCache.shared,
        deduplicator: Deduplicator<URL, DataResponse> =
        Deduplicator<URL, DataResponse>()
    ) {
        self.loader = loader
        self.cache  = cache
        self.dedup  = deduplicator
        Self.log.debug("ImagePipeline initialised")
    }

    // MARK: Public API
    public func image(from url: URL,
                      progress: @escaping ProgressHandler) async throws -> UIImage
    {
        Self.log.debug("Request for \(url, privacy: .public)")

        for try await event in load(from: url, progress: progress) {
            switch event {
            case .finished(let img):
                Self.log.info("✅ Finished \(url, privacy: .public) size=\(img.size.debugDescription, privacy: .public)")
                return img

            case .failure(let err):
                Self.log.error("❌ Failed \(url, privacy: .public): \(err, privacy: .public)")
                throw err
            }
        }

        Self.log.notice("Download cancelled \(url, privacy: .public)")
        throw CancellationError()
    }

    // MARK: Stream Events
    enum Event: Sendable {
        case finished(UIImage)
        case failure(PipelineError)
    }

    // MARK: Errors
    enum PipelineError: Error {
        case badHTTPStatus(Int)
        case decodingFailed
        case underlying(Error)
    }

    // MARK: Private Helpers
    private func load(from url: URL,
                      progress: ProgressHandler?) -> AsyncStream<Event>
    {
        AsyncStream { continuation in
            let task = Task { [cache, loader, dedup] in
                do {
                    if let cached = try await cache.image(for: url) {
                        Self.log.debug("Cache-hit \(url, privacy: .public)")
                        continuation.yield(.finished(cached))
                        continuation.finish()
                        return
                    }
                    Self.log.debug("Cache-miss \(url, privacy: .public)")

                    let (data, response): DataResponse = try await dedup.run(key: url) {
                        try await loader.data(for: url) { received, total in
                            guard let total, let progress, !Task.isCancelled else { return }
                            let fraction = Double(received) / Double(total)
                            progress(fraction)
                        }
                    }

                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode)
                    {
                        throw PipelineError.badHTTPStatus(http.statusCode)
                    }

                    //TODO: Compress the image
                    guard let image = UIImage(data: data) else {
                        throw PipelineError.decodingFailed
                    }

                    try await cache.insert(image, for: url)
                    continuation.yield(.finished(image))
                    continuation.finish()

                } catch is CancellationError {
                    Self.log.notice("Task cancelled \(url, privacy: .public)")
                    continuation.finish()
                } catch let err as PipelineError {
                    continuation.yield(.failure(err))
                    continuation.finish()
                } catch {
                    continuation.yield(.failure(.underlying(error)))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
