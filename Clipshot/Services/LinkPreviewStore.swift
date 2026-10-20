import AppKit
import Combine
import Foundation

struct LinkPreview {
    let image: NSImage?
    let title: String?
    let description: String?

    var hasMetadata: Bool {
        title != nil || description != nil
    }
}

/// App-wide Open Graph preview state. Keeps decoded images and metadata in
/// memory and dedupes in-flight fetches; network work happens off-main.
@MainActor
final class LinkPreviewStore: ObservableObject {
    @Published private(set) var revision = 0

    private let loader: OGImageLoader
    private var previews: [URL: LinkPreview] = [:]
    private var failed: Set<URL> = []
    private var inFlight: Set<URL> = []
    private var tasks: [URL: Task<Void, Never>] = [:]

    private(set) var isPaused = false

    init(loader: OGImageLoader = OGImageLoader()) {
        self.loader = loader
    }

    func preview(for url: URL) -> LinkPreview? {
        previews[url]
    }

    func cachedImage(for url: URL) -> NSImage? {
        previews[url]?.image
    }

    func request(for url: URL, enabled: Bool) {
        guard enabled, !isPaused else { return }
        guard previews[url] == nil, !failed.contains(url), !inFlight.contains(url) else { return }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

        inFlight.insert(url)
        let loader = self.loader
        let task = Task.detached(priority: .utility) { [self] in
            let page = await loader.preview(for: url)
            if Task.isCancelled { return }
            await MainActor.run {
                self.inFlight.remove(url)
                self.tasks.removeValue(forKey: url)
                if let page {
                    let image = page.imageData.flatMap { NSImage(data: $0) }
                    self.previews[url] = LinkPreview(
                        image: image,
                        title: page.metadata.title,
                        description: page.metadata.description
                    )
                } else {
                    self.failed.insert(url)
                }
                self.revision &+= 1
            }
        }
        tasks[url] = task
    }

    /// Pausing cancels in-flight fetches and blocks new ones (privacy mode).
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        if paused {
            for task in tasks.values {
                task.cancel()
            }
            tasks.removeAll()
            inFlight.removeAll()
        }
    }

    func clearCache() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        inFlight.removeAll()
        previews.removeAll()
        failed.removeAll()
        revision &+= 1

        let loader = self.loader
        Task.detached(priority: .utility) {
            loader.clearCache()
        }
    }
}
