import AppKit
import CryptoKit
import Foundation

struct CapturedPayload {
    let kind: ClipboardItemKind
    let text: String?
    let title: String?
    let dataPath: String?
    let hash: String
}

/// Type sniffing + dedupe hashing for NSPasteboard contents.
enum ClipboardPayloadReader {
    static let colorType = NSPasteboard.PasteboardType("com.apple.cocoa.pasteboard.color")

    static func read(from pasteboard: NSPasteboard, dataStore: ItemDataStore) -> CapturedPayload? {
        // Finder file copies arrive as file URLs.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let first = urls.first {
            let text = urls.count == 1
                ? first.absoluteString
                : urls.map(\.absoluteString).joined(separator: "\n")
            return CapturedPayload(
                kind: .file,
                text: text,
                title: urls.count == 1 ? first.lastPathComponent : "\(urls.count) files",
                dataPath: nil,
                hash: hash(kind: .file, strings: [text])
            )
        }

        // Images, normalized to PNG.
        if let imageData = pngData(from: pasteboard) {
            let digest = hash(kind: .image, data: imageData)
            let path = dataStore.save(imageData, fileExtension: "png", hash: digest)
            let size = NSBitmapImageRep(data: imageData).map { "\($0.pixelsWide)×\($0.pixelsHigh)" }
            return CapturedPayload(
                kind: .image,
                text: nil,
                title: size.map { "Image \($0)" } ?? "Image",
                dataPath: path,
                hash: digest
            )
        }

        // Rich text, with the plain-text representation kept for search/paste.
        if let rtf = pasteboard.data(forType: .rtf) {
            let plain = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string
                ?? pasteboard.string(forType: .string)
            let digest = hash(kind: .rtf, data: rtf)
            let path = dataStore.save(rtf, fileExtension: "rtf", hash: digest)
            return CapturedPayload(
                kind: .rtf,
                text: plain,
                title: nil,
                dataPath: path,
                hash: digest
            )
        }

        // Colors (e.g. copied from color pickers).
        if pasteboard.types?.contains(colorType) == true,
           let colorData = pasteboard.data(forType: colorType),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData),
           let hex = hexString(from: color) {
            return CapturedPayload(
                kind: .color,
                text: hex,
                title: "Color \(hex)",
                dataPath: nil,
                hash: hash(kind: .color, strings: [hex])
            )
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let kind: ClipboardItemKind
            if ClipboardColorParser.parse(string) != nil {
                kind = .color
            } else if detectURL(in: string) != nil {
                kind = .url
            } else {
                kind = .text
            }
            return CapturedPayload(
                kind: kind,
                text: string,
                title: nil,
                dataPath: nil,
                hash: hash(kind: kind, strings: [string])
            )
        }

        return nil
    }

    static func detectURL(in string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 4096, !trimmed.contains(where: \.isWhitespace) else {
            return nil
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              host.contains("."),
              !host.hasPrefix(".")
        else { return nil }
        return url
    }

    static func hash(kind: ClipboardItemKind, strings: [String]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        for string in strings {
            hasher.update(data: Data(string.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hash(kind: ClipboardItemKind, data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func hexString(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
