import AppKit
import SwiftUI

struct ItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var appIcons: AppIconProvider
    @ObservedObject var clipImages: ClipImageStore
    let linkPreviews: LinkPreviewStore
    let fetchLinkPreviews: Bool
    let isPaused: Bool

    let onSelect: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPlainPaste: () -> Void
    let onShorten: () -> Void
    let onQR: () -> Void
    let onQROriginal: () -> Void
    let onPin: () -> Void
    let onAddToPinboard: (Pinboard) -> Void
    let onRemoveFromPinboard: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void
    let onAddToStack: () -> Void
    let pinboards: [Pinboard]

    private static let minimumWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                CardBand(
                    icon: appIcons.icon(for: item.bundleId),
                    sourceApp: item.sourceApp ?? "Unknown",
                    kind: item.kind,
                    relativeTime: relativeTime,
                    accent: appIcons.accent(for: item.bundleId),
                    isSelected: isSelected,
                    isPinned: item.isPinned,
                    hasShortLink: item.hasShortLink,
                    isSnippet: item.isSnippet,
                    compact: compact
                )

                preview
                    .padding(
                        .horizontal,
                        item.kind == .color ? 0 : CardChromeStyle.bodyHorizontalPadding
                    )
                    .padding(
                        .vertical,
                        item.kind == .color ? 0 : CardChromeStyle.bodyVerticalPadding
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPaste() }
            .onTapGesture { onSelect() }

            CardFooter(
                kind: item.kind,
                isPinned: item.isPinned,
                compact: compact,
                onCopy: onCopy,
                onPaste: onPaste,
                onPin: onPin,
                onPlainPaste: onPlainPaste,
                onShorten: onShorten,
                onQR: onQR,
                onAddToStack: onAddToStack,
                onEdit: onEdit,
                onRename: onRename
            )
        }
        .frame(width: max(Self.minimumWidth, compact ? 138 : 204))
        .frame(maxHeight: .infinity)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CardChromeStyle.cornerRadius,
                style: .continuous
            )
        )
        .overlay(cardBorder)
        .contextMenu { contextMenu }
        .help(item.displayText)
        .onAppear {
            appIcons.ensureLoaded(bundleId: item.bundleId)
            clipImages.ensureLoaded(path: item.dataPath)
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? Color.primary.opacity(0.09)
                    : Color.primary.opacity(0.05)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(
            cornerRadius: CardChromeStyle.cornerRadius,
            style: .continuous
        )
        .stroke(
            borderColor,
            lineWidth: CardAccentStyle.borderWidth(isSelected: isSelected)
        )
    }

    private var borderColor: Color {
        if let tint = CardAccentStyle.borderTint(
            for: accentNSColor,
            isSelected: isSelected
        ) {
            return tint.color
        }
        if isSelected { return Color.accentColor.opacity(0.9) }
        return Color.primary.opacity(0.12)
    }

    private var accentNSColor: NSColor? {
        appIcons.accent(for: item.bundleId)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .color:
            if let text = item.text, let parsed = ClipboardColorParser.parse(text) {
                let background = colorScheme == .dark
                    ? ColorCardStyle.darkBackground
                    : ColorCardStyle.lightBackground
                let foreground = ColorCardStyle.foreground(for: parsed, over: background)
                let foregroundColor = Color(nsColor: ColorCardStyle.swiftUIColor(for: foreground))

                Rectangle()
                    .fill(Color(nsColor: parsed.nsColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        Text(text)
                            .font(.system(
                                size: compact ? 14 : 17,
                                weight: .semibold,
                                design: .monospaced
                            ))
                            .foregroundStyle(foregroundColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        (foreground == .black ? Color.white : Color.black)
                                            .opacity(0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            } else {
                fallbackPreview
            }
        case .url:
            URLPreviewView(
                previews: linkPreviews,
                url: item.url,
                enabled: fetchLinkPreviews,
                isPaused: isPaused,
                compact: compact,
                fallbackText: item.previewText
            )
        case .image:
            if let image = clipImages.image(forPath: item.dataPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 46 : 78)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                fallbackPreview
            }
        case .file:
            HStack(spacing: 5) {
                Image(systemName: "doc.fill")
                    .font(.system(size: compact ? 21 : 26))
                    .foregroundStyle(.secondary)
                Text(item.title ?? item.previewText)
                    .font(.system(size: compact ? 13 : 14.5))
                    .lineLimit(compact ? 3 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(item.previewText)
                .font(.system(size: compact ? 13 : 14.5))
                .lineLimit(compact ? 4 : 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.disabled)
        }
    }

    private var fallbackPreview: some View {
        Text(item.title ?? item.kind.displayName)
            .font(.system(size: 14.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Paste") { onPaste() }
        Button("Paste as Plain Text") { onPlainPaste() }
        Button("Copy") { onCopy() }
        Divider()
        if item.kind == .url {
            Button("Shorten…") { onShorten() }
            if item.hasShortLink {
                Button("Copy Short Link") {
                    if let shortUrl = item.shortUrl {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shortUrl, forType: .string)
                    }
                }
            }
        }
        if item.kind != .color {
            Button("Show QR Code") { onQR() }
            if item.hasShortLink, item.kind == .url {
                Button("Show QR Code for Original URL") { onQROriginal() }
            }
        }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
        Menu("Add to Pinboard") {
            if pinboards.isEmpty {
                Text("No pinboards yet")
            }
            ForEach(pinboards) { pinboard in
                Button(pinboard.name) { onAddToPinboard(pinboard) }
            }
        }
        if item.pinboardId != nil {
            Button("Remove from Pinboard") { onRemoveFromPinboard() }
        }
        Button("Add to Paste Stack") { onAddToStack() }
        Divider()
        if item.kind == .text || item.kind == .url {
            Button("Edit…") { onEdit() }
        }
        Button("Rename…") { onRename() }
        Button("Delete", role: .destructive) { onDelete() }
    }
}

/// OG image + title + description for URL cards. Partial metadata is shown as
/// available; when nothing is cached/fetched, the URL itself is the fallback.
private struct URLPreviewView: View {
    /// Standard Open Graph image ratio (1200×630).
    static let aspectRatio: CGFloat = 120.0 / 63.0

    @ObservedObject var previews: LinkPreviewStore
    let url: URL?
    let enabled: Bool
    let isPaused: Bool
    let compact: Bool
    let fallbackText: String

    private var preview: LinkPreview? {
        guard let url else { return nil }
        return previews.preview(for: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The raw URL is the first-paint fallback. Metadata (and the image)
            // enrich the card afterward without delaying the item itself.
            if preview?.title == nil, preview?.description == nil {
                Text(fallbackText)
                    .font(.system(size: compact ? 12.5 : 13.5))
                    .lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            thumbnail

            if let title = preview?.title {
                Text(title)
                    .font(.system(size: compact ? 13 : 14.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let description = preview?.description {
                Text(description)
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onChange(of: isPaused) { _, paused in
            if !paused { refresh() }
        }
        .onChange(of: enabled) { _, isEnabled in
            if isEnabled { refresh() }
        }
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))

                    if let image = preview?.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 19.5, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    private func refresh() {
        guard let url else { return }
        // Let the item and its raw URL paint before any preview/network work.
        DispatchQueue.main.async {
            previews.request(for: url, enabled: enabled)
        }
    }
}
