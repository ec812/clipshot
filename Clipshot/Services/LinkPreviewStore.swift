import AppKit
import Combine
import Foundation

/// App-wide Open Graph preview state. Keeps decoded images in memory and
/// dedupes in-flight fetches; the heavy lifting happens off the main actor.
@MainActor
final class LinkPreviewStore: ObservableObject {
    @Published private(set) var revision = 0

    private let loader: OGImageLoader
    private var memory: [URL: NSImage] = [:]
    private var failed: Set<URL> = []
    private var inFlight: Set<URL> = []
    private var tasks: [URL: Task<Void, Never>] = [:]

    private(set) var isPaused = false

    init(loader: OGImageLoader = OGImageLoader()) {
        self.loader = loader
    }

    func cachedImage(for url: URL) -> NSImage? {
        memory[url]
    }

    func request(for url: URL, enabled: Bool) {
        guard enabled, !isPaused else { return }
        guard memory[url] == nil, !failed.contains(url), !inFlight.contains(url) else { return }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

        inFlight.insert(url)
        let loader = self.loader
        let task = Task.detached(priority: .utility) { [self] in
            let data = await loader.imageData(for: url)
            if Task.isCancelled { return }
            await MainActor.run {
                self.inFlight.remove(url)
                self.tasks.removeValue(forKey: url)
                if let data, let image = NSImage(data: data) {
                    self.memory[url] = image
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
        memory.removeAll()
        failed.removeAll()
        revision &+= 1

        let loader = self.loader
        Task.detached(priority: .utility) {
            loader.clearCache()
        }
    }
}
