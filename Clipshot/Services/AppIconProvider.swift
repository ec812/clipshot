import AppKit
import Combine
import CryptoKit
import Foundation

/// Extracts a stable accent color from an app icon.
enum AppIconAccent {
    /// Returns nil for empty/transparent or effectively grayscale/white/black icons.
    static func dominantAccent(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return dominantAccent(from: cgImage)
    }

    static func dominantAccent(from cgImage: CGImage) -> NSColor? {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var totalWeight = 0.0
        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha >= 0.5 else { continue }

            var red = Double(pixels[index]) / 255
            var green = Double(pixels[index + 1]) / 255
            var blue = Double(pixels[index + 2]) / 255

            // Undo premultiplication for partially transparent pixels.
            if alpha > 0, alpha < 1 {
                red = min(red / alpha, 1)
                green = min(green / alpha, 1)
                blue = min(blue / alpha, 1)
            }

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

            // Reject near-white, near-black, and gray pixels.
            guard maximum >= 0.12, minimum <= 0.88, saturation >= 0.18 else { continue }

            let weight = saturation
            redSum += red * weight
            greenSum += green * weight
            blueSum += blue * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }

        let red = redSum / totalWeight
        let green = greenSum / totalWeight
        let blue = blueSum / totalWeight

        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
        guard maximum >= 0.1, saturation >= 0.1 else { return nil }

        return NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }
}

/// Resolves, caches, and accents source-app icons by bundle id.
///
/// Icon lookup happens on the main actor (cheap and NSWorkspace-based); the
/// pixel pass for the accent runs off the main actor. Both results are cached
/// in memory and on disk.
@MainActor
final class AppIconProvider: ObservableObject {
    @Published private(set) var revision = 0

    private let cacheDirectory: URL
    private let genericIcon: NSImage
    private var icons: [String: NSImage] = [:]
    private var accents: [String: NSColor] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = base
                .appendingPathComponent("Clipshot", isDirectory: true)
                .appendingPathComponent("AppIcons", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory,
            withIntermediateDirectories: true
        )
        self.genericIcon = NSImage(named: NSImage.applicationIconName)
            ?? NSImage(size: NSSize(width: 32, height: 32))
    }

    func icon(for bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return genericIcon }
        if let icon = icons[bundleId] {
            return icon
        }
        return missing.contains(bundleId) ? genericIcon : nil
    }

    func accent(for bundleId: String?) -> NSColor? {
        guard let bundleId else { return nil }
        return accents[bundleId]
    }

    func ensureLoaded(bundleId: String?) {
        guard let bundleId, !bundleId.isEmpty else { return }
        guard icons[bundleId] == nil, !missing.contains(bundleId), !inFlight.contains(bundleId) else {
            return
        }
        inFlight.insert(bundleId)

        let iconURL = Self.fileURL(bundleId: bundleId, suffix: "png", in: cacheDirectory)
        let accentURL = Self.fileURL(bundleId: bundleId, suffix: "accent", in: cacheDirectory)

        var icon: NSImage?
        var pngToWrite: Data?

        if let data = try? Data(contentsOf: iconURL), let cached = NSImage(data: data) {
            icon = cached
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let fetched = NSWorkspace.shared.icon(forFile: appURL.path)
            icon = fetched
            pngToWrite = Self.pngData(fetched)
        }

        inFlight.remove(bundleId)

        guard let icon else {
            missing.insert(bundleId)
            revision &+= 1
            return
        }

        icons[bundleId] = icon
        revision &+= 1

        if let pngToWrite {
            let url = iconURL
            Task.detached(priority: .utility) {
                try? pngToWrite.write(to: url, options: .atomic)
            }
        }

        if let cachedAccent = Self.readAccent(from: accentURL) {
            accents[bundleId] = cachedAccent
            revision &+= 1
            return
        }

        guard let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        Task.detached(priority: .utility) { [self] in
            guard let accent = AppIconAccent.dominantAccent(from: cgImage) else { return }
            Self.writeAccent(accent, to: accentURL)
            await MainActor.run {
                self.accents[bundleId] = accent
                self.revision &+= 1
            }
        }
    }

    // MARK: - Disk cache

    private static func fileURL(bundleId: String, suffix: String, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(bundleId.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(key).\(suffix)")
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff)
        else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private static func readAccent(from url: URL) -> NSColor? {
        guard let string = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let components = string
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard components.count == 3 else { return nil }
        return NSColor(
            srgbRed: CGFloat(components[0]),
            green: CGFloat(components[1]),
            blue: CGFloat(components[2]),
            alpha: 1
        )
    }

    private nonisolated static func writeAccent(_ color: NSColor, to url: URL) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let string = "\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent)"
        try? string.write(to: url, atomically: true, encoding: .utf8)
    }
}
