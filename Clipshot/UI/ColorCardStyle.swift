import AppKit
import Foundation

enum ColorCardForeground: Equatable {
    case black
    case white
}

/// Pure styling rules for color items.
enum ColorCardStyle {
    static let darkBackground = ParsedColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)!
    static let lightBackground = ParsedColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)!

    /// WCAG relative luminance of an sRGB color.
    static func relativeLuminance(_ color: ParsedColor) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    /// Choose the foreground with the higher WCAG contrast ratio.
    /// Luminance 0.179 is the crossover where black and white contrast tie.
    /// Translucent colors are composited over the card background first.
    static func foreground(
        for color: ParsedColor,
        over background: ParsedColor = darkBackground
    ) -> ColorCardForeground {
        let alpha = color.alpha
        let effective = ParsedColor(
            red: color.red * alpha + background.red * (1 - alpha),
            green: color.green * alpha + background.green * (1 - alpha),
            blue: color.blue * alpha + background.blue * (1 - alpha),
            alpha: 1
        ) ?? color
        return relativeLuminance(effective) > 0.179 ? .black : .white
    }

    static func swiftUIColor(for foreground: ColorCardForeground) -> NSColor {
        foreground == .black ? .black : .white
    }
}
