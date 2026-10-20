import CryptoKit
import Foundation

enum OGImageCacheResult: Equatable {
    case preview(OGPagePreview)
    case negative
    case miss
}

/// Disk cache for Open Graph previews (image + metadata JSON) with TTL,
/// negative caching, and an LRU size cap.
///
/// Metadata is the canonical entry; the image file is optional. Reading a hit
/// never extends TTL (which uses the metadata modification date); LRU order is
/// tracked with a tiny `.access` sidecar.
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
    }

    static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Clipshot", isDirectory: true)
            .appendingPathComponent("OGCache", isDirectory: true)
    }

    // MARK: - Public API

    func lookup(url: URL) -> OGImageCacheResult {
        queue.sync {
            ensureDirectoryLocked()
            let metadataURL = metadataFileURL(for: url)
            let imageURL = imageFileURL(for: url)
            let negativeURL = negativeFileURL(for: url)
            let accessURL = accessFileURL(for: url)
            let referenceDate = now()

            if fileManager.fileExists(atPath: metadataURL.path) {
                let storedAt = modificationDate(of: metadataURL) ?? .distantPast
                if referenceDate.timeIntervalSince(storedAt) <= ttl {
                    touch(accessURL, at: referenceDate)
                    if let data = try? Data(contentsOf: metadataURL),
                       let metadata = try? JSONDecoder().decode(OGMetadata.self, from: data) {
                        let imageData: Data?
                        if fileManager.fileExists(atPath: imageURL.path) {
                            imageData = try? Data(contentsOf: imageURL)
                        } else {
                            imageData = nil
                        }
                        return .preview(OGPagePreview(imageData: imageData, metadata: metadata))
                    }
                }
                removeEntry(
                    metadataURL: metadataURL,
                    imageURL: imageURL,
                    negativeURL: negativeURL,
                    accessURL: accessURL
                )
            } else if fileManager.fileExists(atPath: imageURL.path) {
                // Legacy image-only cache entry: drop it so the page is refetched
                // once and upgraded with title/description metadata.
                removeEntry(
                    metadataURL: metadataURL,
                    imageURL: imageURL,
                    negativeURL: negativeURL,
                    accessURL: accessURL
                )
            }

            if fileManager.fileExists(atPath: negativeURL.path) {
                let storedAt = modificationDate(of: negativeURL) ?? .distantPast
                if referenceDate.timeIntervalSince(storedAt) <= negativeTTL {
                    return .negative
                }
                removeEntry(
                    metadataURL: metadataURL,
                    imageURL: imageURL,
                    negativeURL: negativeURL,
                    accessURL: accessURL
                )
            }

            return .miss
        }
    }

    func storePreview(_ preview: OGPagePreview, for url: URL) {
        queue.sync {
            ensureDirectoryLocked()
            guard !preview.isEmpty else {
                storeFailureLocked(for: url)
                return
            }

            let metadataURL = metadataFileURL(for: url)
            let imageURL = imageFileURL(for: url)
            let negativeURL = negativeFileURL(for: url)
            let accessURL = accessFileURL(for: url)

            do {
                let metadataData = try JSONEncoder().encode(preview.metadata)
                try metadataData.write(to: metadataURL, options: .atomic)
                try? fileManager.removeItem(at: negativeURL)

                if let imageData = preview.imageData {
                    try imageData.write(to: imageURL, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: imageURL)
                }

                let timestamp = now()
                touch(metadataURL, at: timestamp)
                if fileManager.fileExists(atPath: imageURL.path) {
                    touch(imageURL, at: timestamp)
                }
                touchOrCreate(accessURL, at: timestamp)
                pruneLocked()
            } catch {
                // If we cannot write, behave as a miss next time.
            }
        }
    }

    /// Convenience for image-only callers/tests.
    func storeImage(_ data: Data, for url: URL) {
        storePreview(OGPagePreview(imageData: data, metadata: OGMetadata()), for: url)
    }

    func storeFailure(for url: URL) {
        queue.sync {
            ensureDirectoryLocked()
            storeFailureLocked(for: url)
        }
    }

    func clear() {
        queue.sync {
            ensureDirectoryLocked()
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
            ensureDirectoryLocked()
            return entryFiles().reduce(0) { $0 + $1.size }
        }
    }

    // MARK: - Paths

    func imageFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url) + ".image")
    }

    func metadataFileURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url) + ".metadata")
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

    private func storeFailureLocked(for url: URL) {
        let metadataURL = metadataFileURL(for: url)
        let imageURL = imageFileURL(for: url)
        let negativeURL = negativeFileURL(for: url)
        let accessURL = accessFileURL(for: url)

        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: imageURL)
        do {
            try Data().write(to: negativeURL, options: .atomic)
            let timestamp = now()
            touch(negativeURL, at: timestamp)
            touchOrCreate(accessURL, at: timestamp)
            pruneLocked()
        } catch {
            // The next lookup will simply retry.
        }
    }

    private func ensureDirectoryLocked() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func modificationDate(of url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date
        else { return nil }
        return date
    }

    private func touch(_ url: URL, at date: Date) {
        if !fileManager.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .atomic)
        }
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func touchOrCreate(_ url: URL, at date: Date) {
        touch(url, at: date)
    }

    private func removeEntry(
        metadataURL: URL,
        imageURL: URL,
        negativeURL: URL,
        accessURL: URL
    ) {
        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: imageURL)
        try? fileManager.removeItem(at: negativeURL)
        try? fileManager.removeItem(at: accessURL)
    }

    private struct Entry {
        let url: URL
        let size: Int
        let accessedAt: Date
    }

    /// One entry per URL: metadata (+ image size) or negative.
    private func entryFiles() -> [Entry] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return [] }

        return contents.compactMap { url -> Entry? in
            let ext = url.pathExtension
            guard ext == "metadata" || ext == "negative" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }

            var size = values.fileSize ?? 0
            if ext == "metadata" {
                let imageURL = url.deletingPathExtension().appendingPathExtension("image")
                if let imageValues = try? imageURL.resourceValues(forKeys: [.fileSizeKey]) {
                    size += imageValues.fileSize ?? 0
                }
            }

            let access = url.deletingPathExtension().appendingPathExtension("access")
            let accessedAt = modificationDate(of: access)
                ?? values.contentModificationDate
                ?? .distantPast
            return Entry(url: url, size: size, accessedAt: accessedAt)
        }
    }

    private func pruneLocked() {
        var entries = entryFiles()
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > sizeLimit else { return }

        entries.sort { $0.accessedAt < $1.accessedAt }
        for entry in entries {
            guard total > sizeLimit else { break }
            let base = entry.url.deletingPathExtension()
            try? fileManager.removeItem(at: entry.url)
            try? fileManager.removeItem(at: base.appendingPathExtension("image"))
            try? fileManager.removeItem(at: base.appendingPathExtension("access"))
            total -= entry.size
        }
    }
}
