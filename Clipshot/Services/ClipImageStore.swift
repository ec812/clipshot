import AppKit
import Combine
import Foundation

/// Loads clipboard image payloads off the main actor and caches them in memory,
/// so timeline scrolling never blocks on reading image files from disk.
@MainActor
final class ClipImageStore: ObservableObject {
    @Published private(set) var revision = 0

    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []

    func image(forPath path: String?) -> NSImage? {
        guard let path else { return nil }
        return images[path]
    }

    func ensureLoaded(path: String?) {
        guard let path, images[path] == nil, !failed.contains(path), !inFlight.contains(path) else {
            return
        }
        inFlight.insert(path)
        let url = URL(fileURLWithPath: path)

        Task.detached(priority: .utility) { [self] in
            let data = try? Data(contentsOf: url)
            await MainActor.run {
                self.inFlight.remove(path)
                if let data, let image = NSImage(data: data) {
                    self.images[path] = image
                } else {
                    self.failed.insert(path)
                }
                self.revision &+= 1
            }
        }
    }
}
