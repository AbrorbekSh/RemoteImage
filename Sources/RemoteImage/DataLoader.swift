import Foundation
import OSLog

// MARK: - DataLoader
protocol DataLoader: Sendable {
    @discardableResult
    func data(
        for url: URL,
        onProgress: @Sendable @escaping (_ received: Int64, _ total: Int64?) -> Void
    ) async throws -> (Data, URLResponse)
}

// MARK: - URLSessionLoader
final class URLSessionLoader: DataLoader {

    // MARK: LoaderError
    enum LoaderError: LocalizedError {
        case invalidStatus(Int)
        case unsupportedResponse
        case cancelled
        var errorDescription: String? {
            switch self {
            case .invalidStatus(let code): return "HTTP \(code)"
            case .unsupportedResponse:     return "Non‑HTTP response"
            case .cancelled:               return "Cancelled"
            }
        }
    }

    // MARK: Properties
    private let session: URLSession
    private let logger: Logger

    // MARK: Initializer
    init(
        session: URLSession = .shared,
        logger: Logger = .init(
            subsystem: "ImagePipeline",
            category: "URLSessionLoader")
    ) {
        self.session = session
        self.logger  = logger
    }

    // MARK: DataLoader
    func data(
        for url: URL,
        onProgress: @Sendable @escaping (Int64, Int64?) -> Void
    ) async throws -> (Data, URLResponse) {

        try Task.checkCancellation()
        logger.debug("⬇️ \(url, privacy: .public)")

        let (byteStream, response) = try await session.bytes(from: url, delegate: nil)

        guard let http = response as? HTTPURLResponse else {
            throw LoaderError.unsupportedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LoaderError.invalidStatus(http.statusCode)
        }

        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        var buffer = Data()
        buffer.reserveCapacity(expected.map(Int.init) ?? 0)

        var chunk: [UInt8] = []
        var received: Int64 = 0

        do {
            for try await byte in byteStream {
                try Task.checkCancellation()
                chunk.append(byte)

                if chunk.count >= 4096 {
                    buffer.append(contentsOf: chunk)
                    received += Int64(chunk.count)
                    chunk.removeAll(keepingCapacity: true)
                    onProgress(received, expected)
                }
            }

            if !chunk.isEmpty {
                buffer.append(contentsOf: chunk)
                received += Int64(chunk.count)
                onProgress(received, expected)
            }

            logger.debug("✅ \(url, privacy: .public) (\(received) bytes)")
            return (buffer, response)

        } catch is CancellationError {
            logger.debug("⚠️ cancelled \(url, privacy: .public)")
            throw LoaderError.cancelled
        }
    }
}
