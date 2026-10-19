import AppKit
import SwiftUI

struct ItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let compact: Bool
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            preview
            Spacer(minLength: 0)
            metadata
            if isSelected {
                actionRow
            }
        }
        .padding(9)
        .frame(width: compact ? 138 : 204)
        .frame(maxHeight: .infinity)
        .background(cardBackground)
        .overlay(cardBorder)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPaste() }
        .onTapGesture { onSelect() }
        .contextMenu { contextMenu }
        .help(item.displayText)
        .onAppear {
            appIcons.ensureLoaded(bundleId: item.bundleId)
            clipImages.ensureLoaded(path: item.dataPath)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(backgroundColor)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(
                borderColor,
                lineWidth: CardAccentStyle.borderWidth(isSelected: isSelected)
            )
    }

    private var backgroundColor: Color {
        if let tint = CardAccentStyle.backgroundTint(for: accentNSColor, isSelected: isSelected) {
            return tint.color
        }
        if isSelected { return Color.accentColor.opacity(0.16) }
        return Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        if let tint = CardAccentStyle.borderTint(for: accentNSColor, isSelected: isSelected) {
            return tint.color
        }
        if isSelected { return Color.accentColor.opacity(0.9) }
        return Color.primary.opacity(0.12)
    }

    private var accentNSColor: NSColor? {
        if item.kind == .color,
           let text = item.text,
           let parsed = ClipboardColorParser.parse(text) {
            return parsed.nsColor
        }
        return appIcons.accent(for: item.bundleId)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(item.kind.displayName.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            if item.isSnippet {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            if item.hasShortLink {
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .color:
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorValue ?? Color.gray.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 42 : 66)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    )
                Text(item.text ?? "")
                    .font(.system(size: compact ? 9 : 10, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        case .url:
            VStack(alignment: .leading, spacing: 5) {
                LinkPreviewThumbnail(
                    previews: linkPreviews,
                    url: item.url,
                    enabled: fetchLinkPreviews,
                    isPaused: isPaused
                )
                Text(item.previewText)
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    .font(.system(size: compact ? 16 : 20))
                    .foregroundStyle(.secondary)
                Text(item.title ?? item.previewText)
                    .font(.system(size: compact ? 10 : 11))
                    .lineLimit(compact ? 3 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(item.previewText)
                .font(.system(size: compact ? 10 : 11))
                .lineLimit(compact ? 4 : 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.disabled)
        }
    }

    private var colorValue: Color? {
        guard item.kind == .color, let text = item.text,
              let parsed = ClipboardColorParser.parse(text)
        else { return nil }
        return Color(nsColor: parsed.nsColor)
    }

    private var fallbackPreview: some View {
        Text(item.title ?? item.kind.displayName)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        HStack(spacing: 3) {
            if let icon = appIcons.icon(for: item.bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: compact ? 9 : 10, height: compact ? 9 : 10)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
            Text(item.sourceApp ?? "Unknown")
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 1)
            Text(relativeTime)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    private var actionRow: some View {
        HStack(spacing: 2) {
            actionButton("doc.on.doc", help: "Copy") { onCopy() }
            actionButton("arrow.down.forward.square", help: "Paste (↩)") { onPaste() }
            if !compact {
                actionButton("textformat", help: "Paste as plain text (⇧↩)") { onPlainPaste() }
            }
            if item.kind == .url {
                actionButton("link.badge.plus", help: "Shorten (⌥⇧S)") { onShorten() }
            }
            if item.kind != .color {
                actionButton("qrcode", help: "QR code (⌥⇧Q)") { onQR() }
            }
            actionButton(item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : "Pin") {
                onPin()
            }
            if !compact {
                actionButton("rectangle.stack.badge.plus", help: "Add to paste stack") { onAddToStack() }
            }
        }
        .padding(.top, 2)
    }

    private func actionButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .medium))
                .frame(width: 17, height: 17)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
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

/// Async OG-image thumbnail with a placeholder while loading, on failure, or
/// when previews are disabled/paused.
private struct LinkPreviewThumbnail: View {
    /// Standard Open Graph image ratio (1200×630).
    static let aspectRatio: CGFloat = 120.0 / 63.0

    @ObservedObject var previews: LinkPreviewStore
    let url: URL?
    let enabled: Bool
    let isPaused: Bool

    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))

                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .onAppear(perform: refresh)
            .onChange(of: previews.revision) { _, _ in
                image = url.flatMap { previews.cachedImage(for: $0) }
            }
            .onChange(of: isPaused) { _, paused in
                if !paused { refresh() }
            }
            .onChange(of: enabled) { _, isEnabled in
                if isEnabled { refresh() }
            }
    }

    private func refresh() {
        guard let url else { return }
        image = previews.cachedImage(for: url)
        if image == nil {
            previews.request(for: url, enabled: enabled)
        }
    }
}
