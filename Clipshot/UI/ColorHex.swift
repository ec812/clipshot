import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

enum PinboardPalette {
    static let colors = [
        "#FF9F0A", "#FF453A", "#BF5AF2", "#0A84FF",
        "#30D158", "#64D2FF", "#FFD60A", "#FF375F"
    ]
}
