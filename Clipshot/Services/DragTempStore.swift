import AppKit
import Foundation
import UniformTypeIdentifiers

/// Owns the copy-on-drag files handed to other apps.
///
/// Location: `<system temp>/ClipshotDrag/`. This is deliberately NOT
/// `ItemDataStore.directory` (Application Support/Clipshot/Data) because
/// `ItemDataStore.pruneOrphans(knownPaths:)` deletes every file there that is
/// not a live item path; a temp copy would be pruned out from under an
/// in-flight drag. The system temp directory also gets cleaned by macOS.
///
/// Copies are swept by age (default 1 hour). They are never removed when the
/// drag ends: drop targets read the file asynchronously, so an age-based sweep
/// is the only safe cleanup.
struct DragTempStore: Sendable {
    static let maxAge: TimeInterval = 60 * 60

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Copies the item's stored image into the drag directory. The file name is
    /// stable and readable so drop targets show something sensible.
    func prepareDragFile(for item: ClipboardItem, now: Date = Date()) -> URL? {
        guard item.kind == .image,
              let sourcePath = item.previewImagePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath))
        else { return nil }

        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        let rawIdentifier = item.id.map(String.init) ?? item.hash
        let identifier = rawIdentifier.filter {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent(
            "clipshot-\(identifier.isEmpty ? "item" : identifier)-\(stamp).png"
        )

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Builds a drag provider carrying BOTH a file URL and image data so file
    /// drop targets (Finder, browser upload pickers) and bitmap targets can
    /// both accept the drag.
    func itemProvider(for item: ClipboardItem) -> NSItemProvider? {
        guard let fileURL = prepareDragFile(for: item) else { return nil }

        let provider = NSItemProvider()
        provider.suggestedName = fileURL.lastPathComponent

        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(fileURL, false, nil)
            return nil
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(fileURL, false, nil)
            return nil
        }

        // NSImage conforms to NSItemProviderWriting, which registers the
        // public.image family for targets that want a bitmap rather than a file.
        if let image = NSImage(contentsOf: fileURL) {
            provider.registerObject(image, visibility: .all)
        }

        return provider
    }

    /// Deletes drag copies older than `maxAge`. Runs at app start so files left
    /// behind by a crash or a failed drop do not accumulate.
    @discardableResult
    func sweepStale(now: Date = Date(), maxAge: TimeInterval = DragTempStore.maxAge) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) else { return [] }

        var removed: [String] = []
        for url in contents {
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey]
            )
            guard let date = values?.contentModificationDate ?? values?.creationDate,
                  now.timeIntervalSince(date) >= maxAge
            else { continue }

            do {
                try FileManager.default.removeItem(at: url)
                removed.append(url.path)
            } catch {
                continue
            }
        }
        return removed
    }
}
