import AppKit
import Foundation
import Quartz

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

/// Quick Look preview for the selected history item.
@MainActor
final class QuickLookPresenter: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private var items: [PreviewItem] = []
    private var temporaryURL: URL?

    func preview(_ item: ClipboardItem, dataStore: ItemDataStore) {
        clearTemporaryFile()

        let url: URL?
        switch item.kind {
        case .image, .rtf:
            if let path = item.dataPath, FileManager.default.fileExists(atPath: path) {
                url = URL(fileURLWithPath: path)
            } else {
                url = nil
            }
        case .file:
            if let text = item.text,
               let first = text.split(separator: "\n").first,
               let fileURL = URL(string: String(first)), fileURL.isFileURL {
                url = fileURL
            } else {
                url = nil
            }
        case .text, .url, .color:
            let text = item.text ?? item.title ?? ""
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipshot-preview-\(UUID().uuidString).txt")
            do {
                try text.write(to: temp, atomically: true, encoding: .utf8)
                temporaryURL = temp
                url = temp
            } catch {
                url = nil
            }
        }

        guard let url else {
            NSSound.beep()
            return
        }

        items = [PreviewItem(url: url, title: item.previewText)]

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    private func clearTemporaryFile() {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
            self.temporaryURL = nil
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 53 {
            panel.orderOut(nil)
            clearTemporaryFile()
            return true
        }
        return false
    }
}
