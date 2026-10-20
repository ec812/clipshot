import AppKit
import SwiftUI

enum CardChromeStyle {
    static let cornerRadius: CGFloat = 14
    static let fullOverlayMinimum: CGFloat = 450

    static let bandHorizontalPadding: CGFloat = 11
    static let bodyHorizontalPadding: CGFloat = 12
    static let bodyVerticalPadding: CGFloat = 10
    static let footerHorizontalPadding: CGFloat = 9

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
            iconButton("doc.on.doc", help: "Copy item", action: onCopy)
            iconButton(
                "doc.on.clipboard",
                help: "Paste item",
                primary: true,
                action: onPaste
            )
            iconButton(
                isPinned ? "pin.fill" : "pin",
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
        _ systemImage: String,
        help: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        FooterIconButton(
            systemImage: systemImage,
            help: help,
            primary: primary,
            size: buttonSize,
            glyphSize: CardChromeStyle.footerGlyphSize(compact: compact),
            action: action
        )
    }
}

private struct FooterIconButton: View {
    let systemImage: String
    let help: String
    let primary: Bool
    let size: CGFloat
    let glyphSize: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var backgroundColor: Color {
        if primary {
            return Color.accentColor.opacity(isHovered ? 0.30 : 0.22)
        }
        return Color.primary.opacity(isHovered ? 0.12 : 0.07)
    }

    private var borderColor: Color {
        primary
            ? Color.accentColor.opacity(isHovered ? 0.65 : 0.45)
            : Color.clear
    }
}
