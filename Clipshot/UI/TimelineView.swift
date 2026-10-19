import AppKit
import SwiftUI

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @FocusState private var searchFocused: Bool

    private var isCompact: Bool {
        appState.settings.alwaysCompact
            || CGFloat(appState.settings.overlayHeight) < OverlayController.compactThreshold
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            Divider().opacity(0.25)
            filterBar
            Divider().opacity(0.15)

            content

            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.thickMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1)))
                    .padding(.top, 26)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.toast)
        .sheet(item: $appState.shortenRequest) { request in
            ShortenSheet(appState: appState, request: request)
        }
        .sheet(item: $appState.editorRequest) { request in
            EditorSheet(appState: appState, request: request)
        }
        .sheet(isPresented: $appState.showNewPinboardSheet) {
            NewPinboardSheet(appState: appState)
        }
        .alert(
            "Clipshot",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            )
        ) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
        .onAppear {
            appState.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
        .onChange(of: appState.searchText) { _, _ in
            appState.scheduleReload()
        }
    }

    private var resizeHandle: some View {
        ResizeHandle(currentHeight: CGFloat(appState.settings.overlayHeight)) { newHeight in
            appState.overlayController.resize(to: newHeight)
        }
        .frame(height: 10)
        .padding(.top, 2)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search clipboard history", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if appState.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 6)

            Menu {
                Button("All types") { appState.filterKind = nil }
                Divider()
                ForEach(ClipboardItemKind.allCases, id: \.self) { kind in
                    Button(kind.displayName) { appState.filterKind = kind }
                }
            } label: {
                filterLabel(
                    appState.filterKind?.displayName ?? "All types",
                    active: appState.filterKind != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !appState.sourceApps.isEmpty {
                Menu {
                    Button("All apps") { appState.filterBundleId = nil }
                    Divider()
                    ForEach(appState.sourceApps, id: \.bundleId) { source in
                        Button(source.sourceApp) { appState.filterBundleId = source.bundleId }
                    }
                } label: {
                    filterLabel(sourceLabel, active: appState.filterBundleId != nil)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button {
                appState.beginNewSnippet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("New text item (⌘N)")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                appState.overlayController.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sourceLabel: String {
        guard let bundleId = appState.filterBundleId else { return "All apps" }
        return appState.sourceApps.first { $0.bundleId == bundleId }?.sourceApp ?? "App"
    }

    private func filterLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
        )
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", selected: isAllSelected) {
                    appState.filterPinnedOnly = false
                    appState.filterPinboardID = nil
                    appState.filterKind = nil
                    appState.filterBundleId = nil
                }
                chip("Pinned", selected: appState.filterPinnedOnly) {
                    appState.filterPinnedOnly.toggle()
                    appState.filterPinboardID = nil
                }
                ForEach(appState.pinboards) { pinboard in
                    Button {
                        if appState.filterPinboardID == pinboard.id {
                            appState.filterPinboardID = nil
                        } else {
                            appState.filterPinboardID = pinboard.id
                            appState.filterPinnedOnly = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: pinboard.colorHex) ?? .orange)
                                .frame(width: 7, height: 7)
                            Text(pinboard.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                appState.filterPinboardID == pinboard.id
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.primary.opacity(0.06)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete pinboard", role: .destructive) {
                            appState.deletePinboard(pinboard)
                        }
                    }
                }
                Button {
                    appState.showNewPinboardSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("New pinboard")

                Spacer(minLength: 8)

                if appState.pasteStack.isActive {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                        Text("Stack: \(appState.pasteStackCount)")
                        Button("Paste next") { appState.pasteNextInStack() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        Button("Clear") { appState.clearPasteStack() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
    }

    private var isAllSelected: Bool {
        appState.filterKind == nil
            && appState.filterBundleId == nil
            && !appState.filterPinnedOnly
            && appState.filterPinboardID == nil
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if appState.items.isEmpty {
            emptyState
        } else {
            timeline
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(appState.items) { item in
                        ItemCard(
                            item: item,
                            isSelected: item.id == appState.selectedItemID,
                            compact: isCompact,
                            appIcons: appState.appIcons,
                            clipImages: appState.clipImages,
                            linkPreviews: appState.linkPreviews,
                            fetchLinkPreviews: appState.settings.fetchLinkPreviews,
                            isPaused: appState.isPaused,
                            onSelect: { appState.select(item) },
                            onPaste: { appState.paste(item) },
                            onCopy: { appState.copy(item) },
                            onPlainPaste: { appState.paste(item, plainText: true) },
                            onShorten: { appState.beginShortening(item) },
                            onQR: { appState.showQR(for: item) },
                            onQROriginal: { appState.showQR(for: item, preferShort: false) },
                            onPin: { appState.togglePin(item) },
                            onAddToPinboard: { pinboard in
                                appState.addToPinboard(item, pinboard: pinboard)
                            },
                            onRemoveFromPinboard: { appState.removeFromPinboard(item) },
                            onDelete: { appState.delete(item) },
                            onEdit: { appState.beginEdit(item) },
                            onRename: { appState.beginRename(item) },
                            onAddToStack: { appState.enqueueForPasteStack([item]) },
                            pinboards: appState.pinboards
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: appState.selectedItemID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.searchText.isEmpty ? "Copy something — it will show up here." : "No matches")
                .font(.system(size: 13, weight: .medium))
            if appState.searchText.isEmpty {
                Text("⌘⇧V opens this timeline · Type to search · ↩ pastes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !appState.accessibilityTrusted {
                Button("Grant Accessibility for direct paste") {
                    appState.requestAccessibility()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            hint("← →", "navigate")
            hint("↩", "paste")
            hint("⇧↩", "plain")
            hint("⌥⇧S", "shorten")
            hint("⌥⇧Q", "QR")
            hint("␣", "preview")
            hint("⌘1–9", "quick paste")
            Spacer()
            Text("\(appState.items.count) items")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if !appState.accessibilityTrusted {
                Button("Accessibility off") { appState.requestAccessibility() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help("Without Accessibility, items are copied instead of pasted")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

struct ResizeHandle: View {
    let currentHeight: CGFloat
    let onResize: (CGFloat) -> Void
    @State private var startHeight: CGFloat?

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = startHeight ?? currentHeight
                        if startHeight == nil {
                            startHeight = start
                        }
                        onResize(start - value.translation.height)
                    }
                    .onEnded { _ in
                        startHeight = nil
                    }
            )
    }
}
