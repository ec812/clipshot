import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PasteOutcome: Equatable {
    case pasted
    case copiedToClipboard
    case failed(String)
}

/// Sequential paste queue used by the Paste Stack feature.
/// Kept free of AppKit so the state machine can be unit tested.
final class PasteStack {
    private(set) var items: [ClipboardItem] = []

    var isActive: Bool { !items.isEmpty }
    var count: Int { items.count }

    func enqueue(_ newItems: [ClipboardItem]) {
        items.append(contentsOf: newItems)
    }

    func popNext() -> ClipboardItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    func peek() -> ClipboardItem? {
        items.first
    }

    func clear() {
        items.removeAll()
    }
}

/// Writes clipboard items and, when Accessibility is granted, synthesizes ⌘V.
/// Without permission the item is left on the clipboard (copy-only fallback),
/// which is the same degradation strategy Paste uses.
@MainActor
final class PasteEngine {
    private let pasteboard: NSPasteboard
    private let accessibilityTrusted: () -> Bool
    private let eventPoster: (CGEvent) -> Void
    private let noteOwnWrite: () -> Void

    init(
        pasteboard: NSPasteboard = .general,
        accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        eventPoster: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        noteOwnWrite: @escaping () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.accessibilityTrusted = accessibilityTrusted
        self.eventPoster = eventPoster
        self.noteOwnWrite = noteOwnWrite
    }

    var hasAccessibilityPermission: Bool {
        accessibilityTrusted()
    }

    @discardableResult
    func paste(_ item: ClipboardItem, plainText: Bool = false, textOverride: String? = nil) async -> PasteOutcome {
        let payloadData = (plainText || textOverride != nil) ? nil : await loadPayloadData(for: item)
        let snapshot = PasteboardSnapshot(pasteboard)
        guard write(item, plainText: plainText, textOverride: textOverride, payloadData: payloadData) else {
            return .failed("This item has no pasteable content.")
        }
        noteOwnWrite()

        guard accessibilityTrusted() else {
            return .copiedToClipboard
        }

        let expectedChangeCount = pasteboard.changeCount
        simulateCommandV()
        restore(snapshot, after: 0.3, expectedChangeCount: expectedChangeCount)
        return .pasted
    }

    func copyToClipboard(_ item: ClipboardItem, textOverride: String? = nil) async {
        let payloadData = textOverride == nil ? await loadPayloadData(for: item) : nil
        _ = write(item, plainText: false, textOverride: textOverride, payloadData: payloadData)
        noteOwnWrite()
    }

    func copyText(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        noteOwnWrite()
    }

    private func loadPayloadData(for item: ClipboardItem) async -> Data? {
        guard item.kind == .rtf || item.kind == .image,
              let path = item.dataPath
        else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: URL(fileURLWithPath: path))
        }.value
    }

    // MARK: - Writing

    private func write(
        _ item: ClipboardItem,
        plainText: Bool,
        textOverride: String?,
        payloadData: Data?
    ) -> Bool {
        pasteboard.clearContents()

        if plainText {
            guard let text = textOverride ?? item.pasteText ?? item.title else { return false }
            pasteboard.setString(text, forType: .string)
            return true
        }

        if let textOverride {
            pasteboard.setString(textOverride, forType: .string)
            if let url = URL(string: textOverride), url.scheme != nil {
                pasteboard.setString(textOverride, forType: .URL)
            }
            return true
        }

        switch item.kind {
        case .text, .color:
            guard let text = item.text else { return false }
            pasteboard.setString(text, forType: .string)
            if item.kind == .color,
               let parsed = ClipboardColorParser.parse(text),
               let data = try? NSKeyedArchiver.archivedData(
                   withRootObject: parsed.nsColor,
                   requiringSecureCoding: false
               ) {
                pasteboard.setData(data, forType: .color)
            }

        case .url:
            guard let text = item.pasteText else { return false }
            pasteboard.setString(text, forType: .string)
            pasteboard.setString(text, forType: .URL)

        case .rtf:
            if let payloadData {
                pasteboard.setData(payloadData, forType: .rtf)
            }
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
            if pasteboard.types?.isEmpty ?? true {
                return false
            }

        case .image:
            guard let payloadData else { return false }
            pasteboard.setData(payloadData, forType: .png)

        case .file:
            guard let text = item.text,
                  let url = URL(string: text) else { return false }
            pasteboard.writeObjects([url as NSURL])
        }

        return true
    }

    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            eventPoster(keyDown)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.flags = .maskCommand
            eventPoster(keyUp)
        }
    }

    private func restore(_ snapshot: PasteboardSnapshot, after delay: TimeInterval, expectedChangeCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Do not clobber a clipboard change the user made while the paste was in flight.
            guard self.pasteboard.changeCount == expectedChangeCount else { return }
            snapshot.restore(to: self.pasteboard)
            self.noteOwnWrite()
        }
    }
}

/// Value snapshot of every pasteboard item/type, used to put the previous
/// clipboard back after a synthetic paste.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let pasteboardItems: [NSPasteboardItem] = items.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}
