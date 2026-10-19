import CryptoKit
import Foundation

enum OGImageCacheResult: Equatable {
    case image(Data)
    case negative
    case miss
}

/// Disk cache for Open Graph images with TTL, negative caching, and an LRU size cap.
/// Keyed by the page URL, not the image URL, so a page only needs one entry.
///
/// TTL is measured from the entry's modification date (set to the injected clock
/// when stored). LRU order is tracked with a tiny `.access` sidecar file so that
/// reading a hit never extends its TTL.
final class OGImageCache: @unchecked Sendable {
    let directory: URL
    let ttl: TimeInterval
    let negativeTTL: TimeInterval
    let sizeLimit: Int

    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.ernest.clipshot.og-image-cache")
    private let fileManager = FileManager.default

    init(
        directory: URL,
        ttl: TimeInterval = 7 * 24 * 60 * 60,
        negativeTTL: TimeInterval = 24 * 60 * 60,
        sizeLimit: Int = 200 * 1024 * 1024,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.ttl = ttl
        self.negativeTTL = negativeTTL
        self.sizeLimit = sizeLimit
        self.now = now
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Clipshot", isDirectory: true)
            .appendingPathComponent("OGCache", isDirectory: true)
    }

    // MARK: - Public API

    func lookup(url: URL) -> OGImageCacheResult {
        queue.sync {
            let imageURL = imageFileURL(for: url)
            let negativeURL = negativeFileURL(for: url)
            let referenceDate = now()

            if fileManager.fileExists(atPath: imageURL.path) {
                let storedAt = modificationDate(of: imageURL) ?? .distantPast
                if referenceDate.timeIntervalSince(storedAt) <= ttl {
                    touch(accessFileURL(for: url), at: referenceDate)
                    if let data = try? Data(contentsOf: imageURL) {
                        return .image(data)
                    }
                    removeEntry(imageURL: imageURL, negativeURL: negativeURL, accessURL: accessFileURL(for: url))
                } else {
                    removeEntry(imageURL: imageURL, negativeURL: negativeURL, accessURL: accessFileURL(for: url))
                }
            }

            if fileManager.fileExists(atPath: negativeURL.path) {
                let storedAt = modificationDate(of: negativeURL) ?? .distantPast
                if referenceDate.timeIntervalSince(storedAt) <= negativeTTL {
                    return .negative
                }
                removeEntry(imageURL: imageURL, negativeURL: negativeURL, accessURL: accessFileURL(for: url))
            }

            return .miss
        }
    }

    func storeImage(_ data: Data, for url: URL) {
        queue.sync {
            let imageURL = imageFileURL(for: url)
            let negativeURL = negativeFileURL(for: url)
            let accessURL = accessFileURL(for: url)
            try? fileManager.removeItem(at: negativeURL)
            do {
                try data.write(to: imageURL, options: .atomic)
                touch(imageURL, at: now())
                touchOrCreate(accessURL, at: now())
                pruneLocked()
            } catch {
                // If we cannot write, behave as a miss next time.
            }
        }
    }

    func storeFailure(for url: URL) {
        queue.sync {
            let imageURL = imageFileURL(for: url)
            let negativeURL = negativeFileURL(for: url)
            let accessURL = accessFileURL(for: url)
            try? fileManager.removeItem(at: imageURL)
            do {
                try Data().write(to: negativeURL, options: .atomic)
                touch(negativeURL, at: now())
                touchOrCreate(accessURL, at: now())
                pruneLocked()
            } catch {
                // Nothing else to do; the next lookup will simply retry.
            }
        }
    }

    func clear() {
        queue.sync {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { return }
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    func currentSize() -> Int {
        queue.sync {
            entryFiles().reduce(0) { $0 + $1.size }
        }
    }

    // MARK: - Paths

    func imageFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url) + ".image")
    }

    func negativeFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url) + ".negative")
    }

    private func accessFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url) + ".access")
    }

    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Locked helpers

    private func modificationDate(of url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date
        else { return nil }
        return date
    }

    private func touch(_ url: URL, at date: Date) {
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func touchOrCreate(_ url: URL, at date: Date) {
        if !fileManager.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .atomic)
        }
        touch(url, at: date)
    }

    private func removeEntry(imageURL: URL, negativeURL: URL, accessURL: URL) {
        try? fileManager.removeItem(at: imageURL)
        try? fileManager.removeItem(at: negativeURL)
        try? fileManager.removeItem(at: accessURL)
    }

    private struct Entry {
        let url: URL
        let size: Int
        let accessedAt: Date
    }

    private func entryFiles() -> [Entry] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return [] }

        return contents.compactMap { url -> Entry? in
            let ext = url.pathExtension
            guard ext == "image" || ext == "negative" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            let access = url.deletingPathExtension().appendingPathExtension("access")
            let accessedAt = modificationDate(of: access)
                ?? values.contentModificationDate
                ?? .distantPast
            return Entry(url: url, size: values.fileSize ?? 0, accessedAt: accessedAt)
        }
    }

    private func pruneLocked() {
        var entries = entryFiles()
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > sizeLimit else { return }

        entries.sort { $0.accessedAt < $1.accessedAt }
        for entry in entries {
            guard total > sizeLimit else { break }
            try? fileManager.removeItem(at: entry.url)
            try? fileManager.removeItem(
                at: entry.url.deletingPathExtension().appendingPathExtension("access")
            )
            total -= entry.size
        }
    }
}
