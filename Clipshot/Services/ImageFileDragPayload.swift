import AppKit
import Foundation
import UniformTypeIdentifiers

/// Drag payload for image cards: vends a concrete on-disk PNG plus pasteboard
/// file-url / filenames types Chromium and Finder expect. Avoids
/// `registerFileRepresentation` for `public.file-url` (SwiftUI crashes there).
final class ImageFileDragPayload: NSObject, NSItemProviderWriting {
    static let filenamesTypeIdentifier = "NSFilenamesPboardType"

    let fileURL: URL
    let dragDirectory: URL

    init(fileURL: URL, dragDirectory: URL) {
        self.fileURL = fileURL
        self.dragDirectory = dragDirectory
    }

    static var writableTypeIdentifiersForItemProvider: [String] {
        [
            UTType.fileURL.identifier,
            filenamesTypeIdentifier,
            UTType.png.identifier,
            UTType.image.identifier,
        ]
    }

    func loadData(
        withTypeIdentifier typeIdentifier: String,
        forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        switch typeIdentifier {
        case UTType.png.identifier, UTType.image.identifier:
            completionHandler(try? Data(contentsOf: fileURL), nil)
        case UTType.fileURL.identifier:
            completionHandler(fileURL.path.data(using: .utf8), nil)
        case Self.filenamesTypeIdentifier:
            let list = [fileURL.path]
            completionHandler(
                try? PropertyListSerialization.data(
                    fromPropertyList: list,
                    format: .binary,
                    options: 0
                ),
                nil
            )
        default:
            completionHandler(nil, NSError(
                domain: "Clipshot",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported type \(typeIdentifier)"]
            ))
        }
        return nil
    }

    func loadFileRepresentation(
        ofType typeIdentifier: String,
        completionHandler: @escaping (URL?, Bool, Error?) -> Void
    ) -> Progress? {
        guard typeIdentifier == UTType.png.identifier else {
            completionHandler(nil, false, nil)
            return nil
        }
        completionHandler(fileURL, false, nil)
        let progress = DragTempStore.cancellableDragProgress(for: fileURL, in: dragDirectory)
        progress.completedUnitCount = 1
        return progress
    }
}
