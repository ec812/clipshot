import AppKit
import Foundation
import UniformTypeIdentifiers

/// Test/dev aid: resolve an `NSItemProvider` onto a pasteboard the way a drop
/// target would by flushing promised data providers, then read types back.
enum DragPasteboardProbe {
    struct Snapshot: Equatable, Sendable {
        let typeStrings: [String]
        let firstFilePathFromNSURL: String?
        let filenamesList: [String]
        let pngByteCount: Int?
    }

    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// One pasteboard item whose promised providers load each registered type.
    static func materialize(_ provider: NSItemProvider) -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        let identifiers = provider.registeredTypeIdentifiers
        guard !identifiers.isEmpty else { return pasteboard }

        let item = NSPasteboardItem()
        let types = identifiers.map { NSPasteboard.PasteboardType($0) }
        item.setDataProvider(
            ItemProviderDataSource(provider: provider),
            forTypes: types
        )
        pasteboard.writeObjects([item])

        let group = DispatchGroup()
        for type in pasteboard.types ?? [] {
            group.enter()
            _ = pasteboard.data(forType: type)
            group.leave()
        }
        group.wait()
        return pasteboard
    }

    /// Pasteboard item used for AppKit drag sessions and probe read-back.
    static func explicitPasteboardItem(fileURL: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(fileURL.path, forType: .fileURL)
        item.setPropertyList([fileURL.path], forType: filenamesType)
        if let data = try? Data(contentsOf: fileURL) {
            item.setData(data, forType: .png)
        }
        return item
    }

    /// Explicit AppKit file drag write (Finder / Chromium-friendly).
    static func materializeExplicitFileDrag(fileURL: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects([explicitPasteboardItem(fileURL: fileURL)])
        return pasteboard
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
        let types = (pasteboard.types ?? []).map(\.rawValue).sorted()
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] ?? []
        let pngBytes = pasteboard.data(forType: .png)?.count
        return Snapshot(
            typeStrings: types,
            firstFilePathFromNSURL: urls?.first?.path,
            filenamesList: filenames,
            pngByteCount: pngBytes
        )
    }
}

private final class ItemProviderDataSource: NSObject, NSPasteboardItemDataProvider {
    let provider: NSItemProvider

    init(provider: NSItemProvider) {
        self.provider = provider
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: type.rawValue) { data, _ in
            if let data {
                item.setData(data, forType: type)
                return
            }
            self.provider.loadFileRepresentation(forTypeIdentifier: type.rawValue) { url, error in
                guard error == nil, let url, let data = try? Data(contentsOf: url) else { return }
                item.setData(data, forType: type)
            }
        }
    }
}
