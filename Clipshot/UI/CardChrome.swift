import AppKit
import SwiftUI

enum CardChromeStyle {
    static let cornerRadius: CGFloat = 14
    static let fullOverlayMinimum: CGFloat = 450
    static let cardWidth: CGFloat = 360

    static let bandHorizontalPadding: CGFloat = 11
    static let bodyHorizontalPadding: CGFloat = 12
    static let bodyVerticalPadding: CGFloat = 10
    static let footerHorizontalPadding: CGFloat = 9

    /// Inner content width available to an image thumbnail.
    static let thumbnailWidth: CGFloat = cardWidth - bodyHorizontalPadding * 2

    /// Height bounds for the thumbnail box. Landscape images fill the width
    /// when the width bound binds and never exceed these heights; portraits
    /// are capped at this height and derive their width from the aspect ratio.
    /// At 1:1 the height cap wins.
    static let thumbnailMaxHeight: CGFloat = 220
    static let compactThumbnailMaxHeight: CGFloat = 200

    /// Contain the image inside `thumbnailWidth × maxHeight`, preserving its
    /// aspect ratio. Landscape images fill the width; portraits are capped.
    static func thumbnailSize(for imageSize: CGSize, compact: Bool) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let maxHeight = compact ? compactThumbnailMaxHeight : thumbnailMaxHeight
        let scale = min(
            thumbnailWidth / imageSize.width,
            maxHeight / imageSize.height
        )
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    static func isCompact(overlayHeight: CGFloat, alwaysCompact: Bool) -> Bool {
        alwaysCompact || overlayHeight < fullOverlayMinimum
    }

    static func bandHeight(compact: Bool) -> CGFloat {
        compact ? 50 : 58
    }

    static func iconSize(compact: Bool) -> CGFloat {
        compact ? 32 : 40
    }

    static func iconCornerRadius(compact: Bool) -> CGFloat {
        compact ? 8 : 10
    }

    static func footerHeight(compact: Bool) -> CGFloat {
        compact ? 32 : 36
    }

    static func footerButtonSize(compact: Bool) -> CGFloat {
        compact ? 26 : 30
    }

    static func footerGlyphSize(compact: Bool) -> CGFloat {
        compact ? 13 : 15
    }

    static func bandTint(
        for accent: NSColor?,
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> AccentTint? {
        guard let rgb = accent?.usingColorSpace(.sRGB) else { return nil }
        let base = colorScheme == .dark ? 0.34 : 0.20
        let opacity = min(0.95, base + (isSelected ? 0.06 : 0))
        return AccentTint(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            opacity: opacity
        )
    }

    static func bandGradient(for tint: AccentTint?) -> LinearGradient {
        if let tint {
            let base = Color(
                red: tint.red,
                green: tint.green,
                blue: tint.blue
            )
            return LinearGradient(
                colors: [
                    base.opacity(tint.opacity),
                    base.opacity(tint.opacity * 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.primary.opacity(0.07),
                Color.primary.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct CardBand: View {
    let icon: NSImage?
    let sourceApp: String
    let kind: ClipboardItemKind
    let relativeTime: String
    let accent: NSColor?
    let isSelected: Bool
    let isPinned: Bool
    let hasShortLink: Bool
    let isSnippet: Bool
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var tint: AccentTint? {
        CardChromeStyle.bandTint(
            for: accent,
            isSelected: isSelected,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceApp)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)

                Text("\(kind.displayName.uppercased()) · \(relativeTime)")
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            statusGlyphs
        }
        .padding(.horizontal, CardChromeStyle.bandHorizontalPadding)
        .frame(height: CardChromeStyle.bandHeight(compact: compact))
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                CardChromeStyle.bandGradient(for: tint)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var appIcon: some View {
        let size = CardChromeStyle.iconSize(compact: compact)

        return Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: compact ? 15 : 18))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CardChromeStyle.iconCornerRadius(compact: compact),
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 2, y: 1)
    }

    @ViewBuilder
    private var statusGlyphs: some View {
        HStack(spacing: 5) {
            if isSnippet {
                Image(systemName: "text.badge.plus")
            }
            if hasShortLink {
                Image(systemName: "link")
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: compact ? 9 : 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

struct CardFooter: View {
    let kind: ClipboardItemKind
    let isPinned: Bool
    let compact: Bool

    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onPlainPaste: () -> Void
    let onShorten: () -> Void
    let onQR: () -> Void
    let onAddToStack: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            iconButton(.lucideCopy, help: "Copy item", action: onCopy)
            iconButton(
                .lucideClipboardPaste,
                help: "Paste item",
                action: onPaste
            )
            iconButton(
                .lucidePin(pinned: isPinned),
                help: isPinned ? "Unpin item" : "Pin item",
                action: onPin
            )
            overflowMenu
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CardChromeStyle.footerHorizontalPadding)
        .frame(height: CardChromeStyle.footerHeight(compact: compact))
        .background(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var buttonSize: CGFloat {
        CardChromeStyle.footerButtonSize(compact: compact)
    }

    private var overflowMenu: some View {
        Menu {
            if kind == .text || kind == .url || kind == .rtf {
                Button {
                    onPlainPaste()
                } label: {
                    Label("Paste as Plain Text", systemImage: "textformat")
                }
            }
            if kind == .url {
                Button {
                    onShorten()
                } label: {
                    Label("Shorten…", systemImage: "link.badge.plus")
                }
            }
            if kind != .color {
                Button {
                    onQR()
                } label: {
                    Label("Show QR Code", systemImage: "qrcode")
                }
            }
            Button {
                onAddToStack()
            } label: {
                Label("Add to Paste Stack", systemImage: "rectangle.stack.badge.plus")
            }
            if kind == .text || kind == .url {
                Button {
                    onEdit()
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
            }
            Button {
                onRename()
            } label: {
                Label("Rename…", systemImage: "character.cursor.ibeam")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(
                    .system(
                        size: CardChromeStyle.footerGlyphSize(compact: compact),
                        weight: .medium
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.07))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private func iconButton(
        _ glyph: FooterGlyph,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        FooterIconButton(
            glyph: glyph,
            help: help,
            size: buttonSize,
            glyphSize: CardChromeStyle.footerGlyphSize(compact: compact),
            action: action
        )
    }
}

private enum FooterGlyph {
    case system(String)
    case lucideCopy
    case lucideClipboardPaste
    case lucidePin(pinned: Bool)
}

private struct FooterIconButton: View {
    let glyph: FooterGlyph
    let help: String
    let size: CGFloat
    let glyphSize: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            glyphView
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: glyphSize, weight: .medium))
        case .lucideCopy:
            LucideCopyShape()
                .stroke(.foreground, style: strokeStyle)
                .frame(width: glyphSize, height: glyphSize)
        case .lucideClipboardPaste:
            LucideClipboardPasteShape()
                .stroke(.foreground, style: strokeStyle)
                .frame(width: glyphSize, height: glyphSize)
        case .lucidePin(let pinned):
            if pinned {
                ZStack {
                    LucidePinShape().fill(.foreground)
                    LucidePinNeedleShape().stroke(.foreground, style: strokeStyle)
                }
                .frame(width: glyphSize, height: glyphSize)
            } else {
                LucidePinShape()
                    .stroke(.foreground, style: strokeStyle)
                    .frame(width: glyphSize, height: glyphSize)
            }
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: glyphSize * 2 / 24,
            lineCap: .round,
            lineJoin: .round
        )
    }

    private var backgroundColor: Color {
        Color.primary.opacity(isHovered ? 0.12 : 0.07)
    }
}

/// Lucide's stroke-style "copy" glyph on its 24x24 grid.
private struct LucideCopyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()
        path.addRoundedRect(
            in: CGRect(
                x: origin.x + 8 * scale,
                y: origin.y + 8 * scale,
                width: 14 * scale,
                height: 14 * scale
            ),
            cornerSize: CGSize(width: 2 * scale, height: 2 * scale)
        )

        path.move(to: point(4, 16))
        path.addCurve(
            to: point(2, 14),
            control1: point(2.9, 16),
            control2: point(2, 15.1)
        )
        path.addLine(to: point(2, 4))
        path.addCurve(
            to: point(4, 2),
            control1: point(2, 2.9),
            control2: point(2.9, 2)
        )
        path.addLine(to: point(14, 2))
        path.addCurve(
            to: point(16, 4),
            control1: point(15.1, 2),
            control2: point(16, 2.9)
        )
        return path
    }
}

private struct LucideGrid {
    let scale: CGFloat
    let origin: CGPoint

    init(rect: CGRect) {
        scale = min(rect.width, rect.height) / 24
        origin = CGPoint(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func length(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

/// Appends a circular SVG arc from the path's current point, preserving the
/// SVG sweep-flag direction in SwiftUI's y-down coordinate space.
private func addLucideArc(
    to end: CGPoint,
    radius: CGFloat,
    sweep: Bool,
    in path: inout Path
) {
    guard let start = path.currentPoint else {
        path.move(to: end)
        return
    }

    let dx = (start.x - end.x) / 2
    let dy = (start.y - end.y) / 2
    let denominator = dx * dx + dy * dy
    guard denominator > 0 else { return }

    let sign: CGFloat = sweep ? 1 : -1
    let factor = sign * sqrt(max(0, (radius * radius - denominator) / denominator))
    let center = CGPoint(
        x: factor * dy + (start.x + end.x) / 2,
        y: factor * -dx + (start.y + end.y) / 2
    )

    let startAngle = atan2(start.y - center.y, start.x - center.x)
    var endAngle = atan2(end.y - center.y, end.x - center.x)
    if sweep {
        while endAngle < startAngle { endAngle += 2 * .pi }
    } else {
        while endAngle > startAngle { endAngle -= 2 * .pi }
    }

    let delta = endAngle - startAngle
    let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
    let step = delta / CGFloat(segments)
    var angle = startAngle

    for _ in 0..<segments {
        let next = angle + step
        let handle = 4 / 3 * tan(step / 4) * radius
        let control1 = CGPoint(
            x: center.x + radius * cos(angle) - handle * sin(angle),
            y: center.y + radius * sin(angle) + handle * cos(angle)
        )
        let control2 = CGPoint(
            x: center.x + radius * cos(next) + handle * sin(next),
            y: center.y + radius * sin(next) - handle * cos(next)
        )
        let endpoint = CGPoint(
            x: center.x + radius * cos(next),
            y: center.y + radius * sin(next)
        )
        path.addCurve(to: endpoint, control1: control1, control2: control2)
        angle = next
    }
}

/// Lucide's "clipboard-paste" glyph on its 24x24 grid.
private struct LucideClipboardPasteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = LucideGrid(rect: rect)
        var path = Path()

        path.move(to: grid.point(11, 14))
        path.addLine(to: grid.point(21, 14))

        path.move(to: grid.point(16, 4))
        path.addLine(to: grid.point(18, 4))
        addLucideArc(to: grid.point(20, 6), radius: grid.length(2), sweep: true, in: &path)
        path.addLine(to: grid.point(20, 7.344))

        path.move(to: grid.point(17, 18))
        path.addLine(to: grid.point(21, 14))
        path.addLine(to: grid.point(17, 10))

        path.move(to: grid.point(8, 4))
        path.addLine(to: grid.point(6, 4))
        addLucideArc(to: grid.point(4, 6), radius: grid.length(2), sweep: false, in: &path)
        path.addLine(to: grid.point(4, 20))
        addLucideArc(to: grid.point(6, 22), radius: grid.length(2), sweep: false, in: &path)
        path.addLine(to: grid.point(18, 22))
        addLucideArc(to: grid.point(19.793, 20.887), radius: grid.length(2), sweep: false, in: &path)

        path.addRoundedRect(
            in: CGRect(
                x: grid.point(8, 2).x,
                y: grid.point(8, 2).y,
                width: grid.length(8),
                height: grid.length(4)
            ),
            cornerSize: CGSize(width: grid.length(1), height: grid.length(1))
        )
        return path
    }
}

/// Lucide's "pin" glyph body on its 24x24 grid.
private struct LucidePinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = LucideGrid(rect: rect)
        var path = Path()

        path.move(to: grid.point(12, 17))
        path.addLine(to: grid.point(12, 22))

        path.move(to: grid.point(9, 10.76))
        addLucideArc(to: grid.point(7.89, 12.55), radius: grid.length(2), sweep: true, in: &path)
        path.addLine(to: grid.point(6.11, 13.45))
        addLucideArc(to: grid.point(5, 15.24), radius: grid.length(2), sweep: false, in: &path)
        path.addLine(to: grid.point(5, 16))
        addLucideArc(to: grid.point(6, 17), radius: grid.length(1), sweep: false, in: &path)
        path.addLine(to: grid.point(18, 17))
        addLucideArc(to: grid.point(19, 16), radius: grid.length(1), sweep: false, in: &path)
        path.addLine(to: grid.point(19, 15.24))
        addLucideArc(to: grid.point(17.89, 13.45), radius: grid.length(2), sweep: false, in: &path)
        path.addLine(to: grid.point(16.11, 12.55))
        addLucideArc(to: grid.point(15, 10.76), radius: grid.length(2), sweep: true, in: &path)
        path.addLine(to: grid.point(15, 7))
        addLucideArc(to: grid.point(16, 6), radius: grid.length(1), sweep: true, in: &path)
        addLucideArc(to: grid.point(16, 2), radius: grid.length(2), sweep: false, in: &path)
        path.addLine(to: grid.point(8, 2))
        addLucideArc(to: grid.point(8, 6), radius: grid.length(2), sweep: false, in: &path)
        addLucideArc(to: grid.point(9, 7), radius: grid.length(1), sweep: true, in: &path)
        path.closeSubpath()

        return path
    }
}

/// The needle that stays visible when the pin is filled.
private struct LucidePinNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = LucideGrid(rect: rect)
        var path = Path()
        path.move(to: grid.point(12, 17))
        path.addLine(to: grid.point(12, 22))
        return path
    }
}
