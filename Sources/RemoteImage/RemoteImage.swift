import SwiftUI
import OSLog

// MARK: - RemoteImage
public struct RemoteImage<Success: View,
                          Placeholder: View,
                          Failure: View>: View {

    // MARK: Logging
    private static var log: Logger {
        Logger(subsystem: "zimran.RemoteImage",
               category: "view")
    }

    // MARK: Public ― View Builders
    private let success: (Image) -> Success
    private let placeholder: () -> Placeholder
    private let failure: (Error) -> Failure

    // MARK: Public ― Behaviour
    private let fadeInDuration: Double?
    private let cancelOnDisappear: Bool
    private let progressHandler: ProgressHandler?
    @Binding private var cancelTrigger: Bool

    // MARK: Dependencies
    private let url: URL
    private let pipeline: ImagePipelineProtocol

    // MARK: State
    @StateObject private var loader: Loader

    // MARK: Initialiser
    init(
        url: URL,
        pipeline: ImagePipelineProtocol = ImagePipeline.shared,
        fadeInDuration: Double? = nil,
        cancelOnDisappear: Bool = false,
        cancelTrigger: Binding<Bool> = .constant(false),
        progress: ProgressHandler? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping (Error) -> Failure,
        @ViewBuilder success: @escaping (Image) -> Success
    ) {
        self.url               = url
        self.pipeline          = pipeline
        self.fadeInDuration    = fadeInDuration
        self.cancelOnDisappear = cancelOnDisappear
        self._cancelTrigger    = cancelTrigger
        self.progressHandler   = progress
        self.placeholder       = placeholder
        self.failure           = failure
        self.success           = success
        _loader                = StateObject(wrappedValue: Loader())
    }

    // MARK: Body
    public var body: some View {
        let _ = Self._printChanges()
        content
            .task {
                await loader.load(from: url,
                                   using: pipeline,
                                   fadeIn: fadeInDuration,
                                   progress: progressHandler)
            }
            .onChange(of: cancelTrigger) { shouldCancel in
                if shouldCancel {
                    Self.log.notice("Manual cancel for \(url, privacy: .public)")
                    loader.cancel()
                }
            }
            .onDisappear {
                if cancelOnDisappear {
                    Self.log.notice("Cancel onDisappear for \(url, privacy: .public)")
                    loader.cancel()
                }
            }
    }

    // MARK: Private Helpers
    @ViewBuilder
    private var content: some View {
        switch loader.phase {
        case .empty:
            placeholder()
        case .success(let uiImage):
            success(Image(uiImage: uiImage))
                .transition(.opacity)
                .animation(fadeInDuration.map { .easeInOut(duration: $0) },
                           value: loader.phase)
        case .failure(let error):
            failure(error)
        }
    }

    var lastError: Binding<Error?> {
        Binding(
            get: { if case .failure(let err) = loader.phase { return err } else { return nil } },
            set: { _ in }
        )
    }
}

// MARK: - Loader (ObservableObject)
extension RemoteImage {
    @MainActor
    final class Loader: ObservableObject {

        // MARK: Logging
        private static var log: Logger {
            Logger(subsystem: "zimran.RemoteImage",
                   category: "loader")
        }
        private static var signposts: OSSignposter {
            OSSignposter(logger: log)
        }

        enum Phase: Equatable {
            case empty
            case success(UIImage)
            case failure(Error)

            static func == (lhs: Phase, rhs: Phase) -> Bool {
                switch (lhs, rhs) {
                case (.empty, .empty):               return true
                case let (.success(a), .success(b)): return a === b
                case let (.failure(e1), .failure(e2)):
                    let n1 = e1 as NSError; let n2 = e2 as NSError
                    return n1.domain == n2.domain && n1.code == n2.code
                default:                             return false
                }
            }
        }

        @Published private(set) var phase: Phase = .empty
        private var task: Task<Void, Never>?

        func load(from url: URL,
                  using pipeline: ImagePipelineProtocol,
                  fadeIn: Double?,
                  progress: ProgressHandler?) async
        {
            guard task == nil else { return }

            let spID = Self.signposts.beginInterval("Load",
                                                    "\(url.absoluteString)")

            task = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    Self.log.debug("Start loading \(url, privacy: .public)")

                    let uiImage = try await pipeline.image(from: url) { fraction in
                        if Task.isCancelled { return }
                        progress?(fraction)
                    }

                    if Task.isCancelled { return }
                    withAnimation(fadeIn.map { .easeInOut(duration: $0) }) {
                        self.phase = .success(uiImage)
                    }
                    Self.log.info("✅ Success \(url, privacy: .public)")

                } catch is CancellationError {
                    Self.log.notice("Cancelled \(url, privacy: .public)")
                    
                } catch {
                    if Task.isCancelled { return }
                    self.phase = .failure(error)
                    Self.log.error("❌ Failure \(url, privacy: .public): \(error, privacy: .public)")
                }
                Self.signposts.endInterval("Load", spID)
            }
        }

        func cancel() {
            task?.cancel()
            task = nil
        }
    }
}

// MARK: - Convenience (UIImage → Image)
extension RemoteImage where
    Success == Image,
    Placeholder == ProgressView<EmptyView, EmptyView>,
    Failure == Image {

    public init(_ url: URL,
                pipeline: ImagePipelineProtocol = ImagePipeline.shared) {
        self.init(url: url,
                  pipeline: pipeline,
                  placeholder: { ProgressView() },
                  failure: { _ in Image(systemName: "exclamationmark.triangle") },
                  success: { $0.resizable() })
    }
}

// MARK: - View Modifiers
extension RemoteImage {

    public func fadeIn(_ duration: Double = 0.25) -> Self {
        Self(url: url,
             pipeline: pipeline,
             fadeInDuration: duration,
             cancelOnDisappear: cancelOnDisappear,
             cancelTrigger: $cancelTrigger,
             progress: progressHandler,
             placeholder: placeholder,
             failure: failure,
             success: success)
    }

    public func cancelOnDisappear(_ enabled: Bool = true) -> Self {
        Self(url: url,
             pipeline: pipeline,
             fadeInDuration: fadeInDuration,
             cancelOnDisappear: enabled,
             cancelTrigger: $cancelTrigger,
             progress: progressHandler,
             placeholder: placeholder,
             failure: failure,
             success: success)
    }

    public func cancelLoading(trigger: Binding<Bool>) -> Self {
        Self(url: url,
             pipeline: pipeline,
             fadeInDuration: fadeInDuration,
             cancelOnDisappear: cancelOnDisappear,
             cancelTrigger: trigger,
             progress: progressHandler,
             placeholder: placeholder,
             failure: failure,
             success: success)
    }

    public func onProgress(_ handler: @escaping ProgressHandler) -> Self {
        Self(url: url,
             pipeline: pipeline,
             fadeInDuration: fadeInDuration,
             cancelOnDisappear: cancelOnDisappear,
             cancelTrigger: $cancelTrigger,
             progress: handler,
             placeholder: placeholder,
             failure: failure,
             success: success)
    }

    public func placeholder<V: View>(
        @ViewBuilder _ builder: @escaping () -> V
    ) -> RemoteImage<Success, V, Failure> {
        RemoteImage<Success, V, Failure>(
            url: url,
            pipeline: pipeline,
            fadeInDuration: fadeInDuration,
            cancelOnDisappear: cancelOnDisappear,
            cancelTrigger: $cancelTrigger,
            progress: progressHandler,
            placeholder: builder,
            failure: failure,
            success: success)
    }

    public func failure<V: View>(
        @ViewBuilder _ builder: @escaping (_ error: Error) -> V
    ) -> RemoteImage<Success, Placeholder, V> {
        RemoteImage<Success, Placeholder, V>(
            url: url,
            pipeline: pipeline,
            fadeInDuration: fadeInDuration,
            cancelOnDisappear: cancelOnDisappear,
            cancelTrigger: $cancelTrigger,
            progress: progressHandler,
            placeholder: placeholder,
            failure: builder,
            success: success)
    }
    
    public func resizable(
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: Image.ResizingMode = .stretch
    ) -> RemoteImage<Image, Placeholder, Failure> {
        RemoteImage<Image, Placeholder, Failure>(
            url: url,
            pipeline: pipeline,
            fadeInDuration: fadeInDuration,
            cancelOnDisappear: cancelOnDisappear,
            cancelTrigger: $cancelTrigger,
            progress: progressHandler,
            placeholder: placeholder,
            failure: failure,
            success: { img in
                img.resizable(capInsets: capInsets, resizingMode: resizingMode)
            })
    }
}
