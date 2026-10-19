import AppKit
import SwiftUI

/// A resolved tint (sRGB components + opacity) used for card styling.
/// Kept free of view state so the rendered values can be unit tested.
struct AccentTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    /// The color a viewer sees when this tint is drawn over a background.
    func composited(over background: (red: Double, green: Double, blue: Double)) -> (red: Double, green: Double, blue: Double) {
        let inverse = 1 - opacity
        return (
            red * opacity + background.red * inverse,
            green * opacity + background.green * inverse,
            blue * opacity + background.blue * inverse
        )
    }
}

/// Visibility spec for per-app accents.
///
/// The original 0.30 border / 0.05 wash was technically present but invisible
/// in dark mode. These values make Safari blue, Notes yellow, etc. immediately
/// recognizable, while the selected card remains stronger (full-opacity border,
/// thicker stroke, deeper wash).
enum CardAccentStyle {
    static let unselectedBorderOpacity = 0.7
    static let unselectedBackgroundOpacity = 0.13
    static let selectedBorderOpacity = 1.0
    static let selectedBackgroundOpacity = 0.22

    static let unselectedBorderWidth: CGFloat = 1.6
    static let selectedBorderWidth: CGFloat = 2.2

    static func borderTint(for accent: NSColor?, isSelected: Bool) -> AccentTint? {
        guard let rgb = accent?.usingColorSpace(.sRGB) else { return nil }
        return AccentTint(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            opacity: isSelected ? selectedBorderOpacity : unselectedBorderOpacity
        )
    }

    static func backgroundTint(for accent: NSColor?, isSelected: Bool) -> AccentTint? {
        guard let rgb = accent?.usingColorSpace(.sRGB) else { return nil }
        return AccentTint(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            opacity: isSelected ? selectedBackgroundOpacity : unselectedBackgroundOpacity
        )
    }

    static func borderWidth(isSelected: Bool) -> CGFloat {
        isSelected ? selectedBorderWidth : unselectedBorderWidth
    }
}
