import Foundation

/// Stores large clipboard payloads (images, RTF) next to the database and
/// keeps only the path in SQLite.
final class ItemDataStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base
                .appendingPathComponent("Clipshot", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func save(_ data: Data, fileExtension: String, hash: String) -> String? {
        let fileName = "\(hash).\(fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    func data(atPath path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    func delete(atPath path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    func pruneOrphans(knownPaths: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !knownPaths.contains(url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
