import AppKit
import Foundation

/// A parsed color in sRGB, independent of AppKit for testability.
struct ParsedColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init?(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        guard red.isFinite, green.isFinite, blue.isFinite, alpha.isFinite else { return nil }
        guard (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue) else { return nil }
        guard (0...1).contains(alpha) else { return nil }
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    var hexRGBA: String {
        String(
            format: "#%02X%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255)),
            Int(round(alpha * 255))
        )
    }
}

/// Parses a clipboard string only when the *entire* trimmed value is one color.
enum ClipboardColorParser {
    static func parse(_ raw: String) -> ParsedColor? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.count <= 128 else { return nil }
        let lower = text.lowercased()

        if lower.hasPrefix("#") {
            return parseHex(lower)
        }
        if let color = parseFunction(lower) {
            return color
        }
        if lower == "transparent" {
            return ParsedColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        if let hex = namedHex[lower] {
            return parseHex(hex)
        }
        return nil
    }

    // MARK: - Hex

    private static func parseHex(_ value: String) -> ParsedColor? {
        guard value.hasPrefix("#") else { return nil }
        let digits = String(value.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        func component(_ pair: Substring) -> Double? {
            Double(Int(pair, radix: 16) ?? -1) / 255
        }

        switch digits.count {
        case 3, 4:
            let chars = Array(digits)
            guard let r = component(Substring(String([chars[0], chars[0]]))),
                  let g = component(Substring(String([chars[1], chars[1]]))),
                  let b = component(Substring(String([chars[2], chars[2]])))
            else { return nil }
            let a: Double
            if chars.count == 4 {
                guard let parsed = component(Substring(String([chars[3], chars[3]]))) else { return nil }
                a = parsed
            } else {
                a = 1
            }
            return ParsedColor(red: r, green: g, blue: b, alpha: a)

        case 6, 8:
            let chars = Array(digits)
            guard let r = component(Substring(String(chars[0...1]))),
                  let g = component(Substring(String(chars[2...3]))),
                  let b = component(Substring(String(chars[4...5])))
            else { return nil }
            let a: Double
            if chars.count == 8 {
                guard let parsed = component(Substring(String(chars[6...7]))) else { return nil }
                a = parsed
            } else {
                a = 1
            }
            return ParsedColor(red: r, green: g, blue: b, alpha: a)

        default:
            return nil
        }
    }

    // MARK: - Functional notation

    private static func parseFunction(_ value: String) -> ParsedColor? {
        guard let match = functionRegex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let nameRange = Range(match.range(at: 1), in: value),
              let bodyRange = Range(match.range(at: 2), in: value)
        else { return nil }

        let name = String(value[nameRange])
        let body = String(value[bodyRange])
        guard let (tokens, alphaToken) = splitComponents(body) else { return nil }

        switch name {
        case "rgb", "rgba":
            return parseRGB(tokens: tokens, alphaToken: alphaToken)
        case "hsl", "hsla":
            return parseHSL(tokens: tokens, alphaToken: alphaToken)
        case "oklch", "okchl":
            return parseOKLCH(tokens: tokens, alphaToken: alphaToken)
        case "oklab":
            return parseOKLab(tokens: tokens, alphaToken: alphaToken)
        default:
            return nil
        }
    }

    private static let functionRegex: NSRegularExpression = {
        // The inner body excludes parentheses so nested functions are rejected.
        try! NSRegularExpression(pattern: #"^(rgba?|hsla?|oklch|okchl|oklab)\s*\(([^()]*)\)$"#, options: [.caseInsensitive])
    }()

    /// Splits `a, b, c / alpha` or `a b c` into three components plus optional alpha.
    private static func splitComponents(_ body: String) -> (tokens: [String], alpha: String?)? {
        var normalized = body.replacingOccurrences(of: ",", with: " ")
        normalized = normalized.replacingOccurrences(of: "/", with: " / ")
        var tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var alpha: String?
        if let slashIndex = tokens.firstIndex(of: "/") {
            guard slashIndex == tokens.count - 2, slashIndex == 3 else { return nil }
            alpha = tokens.last
            tokens.removeLast()
            tokens.removeLast()
        }

        if alpha == nil {
            if tokens.count == 4 {
                alpha = tokens[3]
                tokens.removeLast()
            } else if tokens.count < 2 {
                return nil
            }
        } else if tokens.count != 3 {
            return nil
        }

        return (tokens, alpha)
    }

    private static func parseAlpha(_ token: String?) -> Double? {
        guard let token else { return 1 }
        guard let parsed = numeric(token) else { return nil }
        let value = parsed.isPercent ? parsed.value / 100 : parsed.value
        guard (0...1).contains(value) else { return nil }
        return value
    }

    private static func parseRGB(tokens: [String], alphaToken: String?) -> ParsedColor? {
        guard tokens.count == 3 else { return nil }
        func channel(_ token: String) -> Double? {
            guard let parsed = numeric(token) else { return nil }
            let value = parsed.isPercent ? parsed.value / 100 * 255 : parsed.value
            guard value >= 0, value <= 255 else { return nil }
            return value / 255
        }
        guard let r = channel(tokens[0]),
              let g = channel(tokens[1]),
              let b = channel(tokens[2]),
              let a = parseAlpha(alphaToken)
        else { return nil }
        return ParsedColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func parseHSL(tokens: [String], alphaToken: String?) -> ParsedColor? {
        guard tokens.count == 3 else { return nil }
        guard let hueParsed = numeric(tokens[0], allowDegrees: true), !hueParsed.isPercent else { return nil }
        guard let sat = percentage(tokens[1]), let light = percentage(tokens[2]),
              (0...100).contains(sat), (0...100).contains(light),
              let alpha = parseAlpha(alphaToken)
        else { return nil }

        let h = hueParsed.value.truncatingRemainder(dividingBy: 360)
        let hue = h < 0 ? h + 360 : h
        let s = sat / 100
        let l = light / 100

        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        let (r1, g1, b1): (Double, Double, Double)
        switch hue {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }

        return ParsedColor(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: alpha)
    }

    private static func parseOKLCH(tokens: [String], alphaToken: String?) -> ParsedColor? {
        guard tokens.count == 2 || tokens.count == 3 else { return nil }
        guard let lParsed = numeric(tokens[0]) else { return nil }
        let l = lParsed.isPercent ? lParsed.value / 100 : lParsed.value
        guard (0...1).contains(l) else { return nil }

        guard let cParsed = numeric(tokens[1]), !cParsed.isPercent else { return nil }
        guard (0...0.5).contains(cParsed.value) else { return nil }

        var hue = 0.0
        if tokens.count == 3 {
            guard let hParsed = numeric(tokens[2], allowDegrees: true), !hParsed.isPercent else { return nil }
            hue = hParsed.value
        }
        guard let alpha = parseAlpha(alphaToken) else { return nil }

        let radians = hue * .pi / 180
        let a = cParsed.value * cos(radians)
        let b = cParsed.value * sin(radians)
        return oklabToSRGB(l: l, a: a, b: b, alpha: alpha)
    }

    private static func parseOKLab(tokens: [String], alphaToken: String?) -> ParsedColor? {
        guard tokens.count == 3 else { return nil }
        guard let lParsed = numeric(tokens[0]) else { return nil }
        let l = lParsed.isPercent ? lParsed.value / 100 : lParsed.value
        guard (0...1).contains(l),
              let aParsed = numeric(tokens[1]), !aParsed.isPercent,
              let bParsed = numeric(tokens[2]), !bParsed.isPercent,
              (-0.5...0.5).contains(aParsed.value),
              (-0.5...0.5).contains(bParsed.value),
              let alpha = parseAlpha(alphaToken)
        else { return nil }
        return oklabToSRGB(l: l, a: aParsed.value, b: bParsed.value, alpha: alpha)
    }

    private static func oklabToSRGB(l: Double, a: Double, b: Double, alpha: Double) -> ParsedColor? {
        let lPrime = l + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = l - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = l - 0.0894841775 * a - 1.2914855480 * b

        let l3 = lPrime * lPrime * lPrime
        let m3 = mPrime * mPrime * mPrime
        let s3 = sPrime * sPrime * sPrime

        let rLinear = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let gLinear = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bLinear = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

        func gamma(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            if clamped <= 0.0031308 {
                return 12.92 * clamped
            }
            return 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }

        let r = min(max(gamma(rLinear), 0), 1)
        let g = min(max(gamma(gLinear), 0), 1)
        let bValue = min(max(gamma(bLinear), 0), 1)
        return ParsedColor(red: r, green: g, blue: bValue, alpha: alpha)
    }

    // MARK: - Numbers

    private struct NumericValue {
        let value: Double
        let isPercent: Bool
    }

    private static func numeric(_ token: String, allowDegrees: Bool = false) -> NumericValue? {
        var value = token
        var isPercent = false
        if value.hasSuffix("%") {
            isPercent = true
            value.removeLast()
        } else if allowDegrees, value.hasSuffix("deg") {
            value.removeLast(3)
        } else if allowDegrees, value.hasSuffix("turn") {
            value.removeLast(4)
            guard let parsed = Double(value) else { return nil }
            return NumericValue(value: parsed * 360, isPercent: false)
        }
        guard let parsed = Double(value), parsed.isFinite else { return nil }
        return NumericValue(value: parsed, isPercent: isPercent)
    }

    private static func percentage(_ token: String) -> Double? {
        guard let parsed = numeric(token) else { return nil }
        return parsed.value
    }

    // MARK: - Named colors (CSS subset)

    private static let namedHex: [String: String] = [
        "black": "#000000",
        "silver": "#c0c0c0",
        "gray": "#808080",
        "grey": "#808080",
        "white": "#ffffff",
        "maroon": "#800000",
        "red": "#ff0000",
        "purple": "#800080",
        "fuchsia": "#ff00ff",
        "magenta": "#ff00ff",
        "green": "#008000",
        "lime": "#00ff00",
        "olive": "#808000",
        "yellow": "#ffff00",
        "navy": "#000080",
        "blue": "#0000ff",
        "teal": "#008080",
        "aqua": "#00ffff",
        "cyan": "#00ffff",
        "orange": "#ffa500",
        "rebeccapurple": "#663399",
        "pink": "#ffc0cb",
        "brown": "#a52a2a",
        "gold": "#ffd700",
        "indigo": "#4b0082",
        "violet": "#ee82ee",
        "coral": "#ff7f50",
        "salmon": "#fa8072",
        "khaki": "#f0e68c",
        "lavender": "#e6e6fa",
        "turquoise": "#40e0d0",
        "beige": "#f5f5dc",
        "ivory": "#fffff0",
        "chocolate": "#d2691e",
        "crimson": "#dc143c",
        "darkblue": "#00008b",
        "darkgreen": "#006400",
        "darkred": "#8b0000",
        "lightblue": "#add8e6",
        "lightgreen": "#90ee90",
        "lightyellow": "#ffffe0",
        "lightgray": "#d3d3d3",
        "lightgrey": "#d3d3d3",
        "deepskyblue": "#00bfff",
        "orangered": "#ff4500",
        "hotpink": "#ff69b4",
        "plum": "#dda0dd",
        "seagreen": "#2e8b57",
        "skyblue": "#87ceeb",
        "steelblue": "#4682b4",
        "tomato": "#ff6347",
        "wheat": "#f5deb3",
        "whitesmoke": "#f5f5f5",
        "yellowgreen": "#9acd32"
    ]
}
