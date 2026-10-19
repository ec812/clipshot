import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let store: HistoryStore
    let settings: AppSettings
    let privacyFilter: PrivacyFilter
    let rulesEngine: ShortenRulesEngine
    let dataStore: ItemDataStore
    let keychain: APIKeyStoring
    let registry: ShortenerBackendRegistry
    let monitor: ClipboardMonitor
    let hotkeyManager = HotkeyManager()
    let pasteStack = PasteStack()
    let qrWindowController = QRWindowController()
    let onboardingController = OnboardingWindowController()
    let quickLook = QuickLookPresenter()
    let appIcons = AppIconProvider()
    let linkPreviews = LinkPreviewStore()

    lazy var pasteEngine: PasteEngine = PasteEngine(
        noteOwnWrite: { [weak self] in self?.monitor.noteOwnWrite() }
    )

    lazy var overlayController: OverlayController = OverlayController(appState: self)

    @Published var items: [ClipboardItem] = []
    @Published var selectedItemID: Int64?
    @Published var searchText: String = "" {
        didSet { scheduleReload() }
    }
    @Published var filterKind: ClipboardItemKind? {
        didSet { reload() }
    }
    @Published var filterBundleId: String? {
        didSet { reload() }
    }
    @Published var filterPinnedOnly = false {
        didSet { reload() }
    }
    @Published var filterPinboardID: Int64? {
        didSet { reload() }
    }
    @Published var pinboards: [Pinboard] = []
    @Published var rules: [ShortenRule] = []
    @Published var recentShortLinks: [ShortLink] = []
    @Published var sourceApps: [(bundleId: String, sourceApp: String)] = []
    @Published var toast: String?
    @Published var isPaused = false
    @Published var accessibilityTrusted = false
    @Published var hotkeyError: String?
    @Published var lastError: String?
    @Published var shortenRequest: ShortenRequest?
    @Published var editorRequest: EditorRequest?
    @Published var isShortening = false
    @Published var isVerifyingBackend = false
    @Published var refreshingClickLinkID: String?
    @Published var credentialResult: ShortenerCredentialResult?
    @Published var showNewPinboardSheet = false
    @Published var pasteStackCount = 0

    var isTesting: Bool
    private var startMonitoring: Bool
    private var started = false
    private var reloadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: HistoryStore? = nil,
        settings: AppSettings? = nil,
        keychain: APIKeyStoring? = nil,
        startMonitoring: Bool = true,
        dataStore: ItemDataStore? = nil
    ) {
        let resolvedSettings = settings ?? AppSettings()
        let resolvedKeychain = keychain ?? KeychainStore()

        let resolvedStore: HistoryStore
        if let store {
            resolvedStore = store
        } else {
            do {
                let url = try HistoryStore.defaultDatabaseURL()
                resolvedStore = try HistoryStore(path: url.path)
            } catch {
                NSLog("Clipshot: could not open history database, using memory store: \(error)")
                resolvedStore = try! HistoryStore.inMemory()
            }
        }

        let resolvedDataStore = dataStore ?? ItemDataStore()
        let privacy = PrivacyFilter(configuration: resolvedSettings.privacyConfiguration())
        let rules = ShortenRulesEngine(store: resolvedStore)

        self.store = resolvedStore
        self.settings = resolvedSettings
        self.privacyFilter = privacy
        self.rulesEngine = rules
        self.dataStore = resolvedDataStore
        self.keychain = resolvedKeychain
        self.registry = ShortenerBackendRegistry.shared
        self.startMonitoring = startMonitoring
        self.isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        self.monitor = ClipboardMonitor(
            store: resolvedStore,
            privacyFilter: privacy,
            rulesEngine: rules,
            dataStore: resolvedDataStore
        )

        self.monitor.onCapture = { [weak self] item in
            self?.handleCaptured(item)
        }
        self.monitor.onAutoShorten = { [weak self] item, rule in
            self?.handleAutoShorten(item, rule)
        }

        resolvedSettings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.objectWillChange.send()
                    self.privacyFilter.configuration = self.settings.privacyConfiguration()
                    self.applyActivationPolicy()
                }
            }
            .store(in: &cancellables)

        registry.registerBuiltIns()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        applyActivationPolicy()
        reload()
        refreshAccessibility()
        if !isTesting {
            applyHotkeys()
        }

        if startMonitoring {
            monitor.start()
        }

        _ = try? store.applyRetention(days: settings.retentionDays)
        reload()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility()
            }
        }

        if !settings.hasCompletedOnboarding, !isTesting {
            presentOnboarding()
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    func presentOnboarding() {
        onboardingController.show(appState: self)
    }

    // MARK: - Timeline data

    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        do {
            var loaded = try store.search(
                searchText,
                kind: filterKind,
                bundleId: filterBundleId
            )
            if filterPinnedOnly {
                loaded = loaded.filter(\.isPinned)
            }
            if let pinboard = filterPinboardID {
                loaded = loaded.filter { $0.pinboardId == pinboard }
            }

            items = loaded
            if selectedItemID == nil || !items.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = items.first?.id
            }
            sourceApps = try store.distinctSources()
            pinboards = try store.pinboards()
            rules = try store.shortenRules()
            recentShortLinks = try store.cachedShortLinks(limit: 50)
        } catch {
            lastError = error.localizedDescription
        }
    }

    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == selectedItemID } ?? 0
        let next = min(max(currentIndex + delta, 0), items.count - 1)
        selectedItemID = items[next].id
    }

    func select(_ item: ClipboardItem) {
        selectedItemID = item.id
    }

    private func handleCaptured(_ item: ClipboardItem) {
        if overlayController.isVisible {
            reload()
        }
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        pasteEngine.copyToClipboard(item, textOverride: preferredText(for: item, preferShort: false))
        showToast("Copied")
    }

    func paste(_ item: ClipboardItem, plainText: Bool = false) {
        let override = preferredText(for: item, preferShort: false)
        overlayController.hide()
        let outcome = pasteEngine.paste(item, plainText: plainText, textOverride: override)
        switch outcome {
        case .pasted:
            break
        case .copiedToClipboard:
            showToast("Copied — Accessibility permission is needed to paste directly")
        case .failed(let message):
            showToast(message)
        }
    }

    func pasteSelected(plainText: Bool = false) {
        guard let item = selectedItem else { return }
        paste(item, plainText: plainText)
    }

    func quickPaste(index: Int) {
        guard items.indices.contains(index) else { return }
        paste(items[index])
    }

    private func preferredText(for item: ClipboardItem, preferShort: Bool) -> String? {
        if preferShort, let shortUrl = item.shortUrl, !shortUrl.isEmpty {
            return shortUrl
        }
        return item.text ?? item.title
    }

    func copyToClipboard(_ string: String) {
        pasteEngine.copyText(string)
        showToast("Copied \(string)")
    }

    func togglePin(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            try store.setPinned(!item.isPinned, for: id)
            reload()
            showToast(item.isPinned ? "Unpinned" : "Pinned")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addToPinboard(_ item: ClipboardItem, pinboard: Pinboard) {
        guard let itemID = item.id, let pinboardID = pinboard.id else { return }
        do {
            try store.addItem(itemID, toPinboard: pinboardID)
            reload()
            showToast("Added to \(pinboard.name)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeFromPinboard(_ item: ClipboardItem) {
        guard let itemID = item.id else { return }
        do {
            try store.removeItemFromPinboard(itemID)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            if let path = item.dataPath {
                dataStore.delete(atPath: path)
            }
            try store.deleteItem(id: id)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createPinboard(name: String, colorHex: String) {
        do {
            _ = try store.createPinboard(name: name, colorHex: colorHex)
            pinboards = try store.pinboards()
            showToast("Pinboard created")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deletePinboard(_ pinboard: Pinboard) {
        guard let id = pinboard.id else { return }
        do {
            try store.deletePinboard(id: id)
            if filterPinboardID == id { filterPinboardID = nil }
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Auto-shorten rules

    func saveRule(_ rule: ShortenRule) {
        do {
            _ = try store.saveShortenRule(rule)
            rules = try store.shortenRules()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteRule(_ rule: ShortenRule) {
        guard let id = rule.id else { return }
        do {
            try store.deleteShortenRule(id: id)
            rules = try store.shortenRules()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Credentials

    func apiKey(for backendId: String) -> String? {
        keychain.apiKey(for: backendId)
    }

    func saveAPIKey(_ key: String?, for backendId: String) {
        do {
            try keychain.setAPIKey(key, for: backendId)
            credentialResult = nil
            showToast(key?.isEmpty == false ? "Bitly access token saved" : "Access token removed")
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Paste stack

    func enqueueForPasteStack(_ items: [ClipboardItem]) {
        pasteStack.enqueue(items)
        pasteStackCount = pasteStack.count
        showToast("Added \(items.count) item(s) to paste stack")
    }

    func pasteNextInStack() {
        guard let next = pasteStack.popNext() else {
            pasteStackCount = 0
            showToast("Paste stack is empty")
            return
        }
        pasteStackCount = pasteStack.count
        let override = preferredText(for: next, preferShort: settings.preferShortLinks)
        overlayController.hide()
        _ = pasteEngine.paste(next, plainText: false, textOverride: override)
    }

    func clearPasteStack() {
        pasteStack.clear()
        pasteStackCount = 0
    }

    // MARK: - Editing

    func beginNewSnippet() {
        editorRequest = EditorRequest(mode: .newSnippet, item: nil)
    }

    func beginEdit(_ item: ClipboardItem) {
        editorRequest = EditorRequest(mode: .editText, item: item)
    }

    func beginRename(_ item: ClipboardItem) {
        editorRequest = EditorRequest(mode: .rename, item: item)
    }

    func saveEditor(_ request: EditorRequest, text: String, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch request.mode {
            case .newSnippet:
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let hash = ClipboardPayloadReader.hash(kind: .text, strings: [text])
                _ = try store.insert(
                    kind: .text,
                    text: text,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    sourceApp: "Clipshot",
                    bundleId: "com.ernest.clipshot",
                    hash: hash,
                    isSnippet: true
                )
            case .editText:
                guard let item = request.item, let id = item.id else { return }
                try store.updateText(text, title: trimmedTitle.isEmpty ? nil : trimmedTitle, for: id)
            case .rename:
                guard let item = request.item, let id = item.id else { return }
                try store.rename(trimmedTitle, for: id)
            }
            editorRequest = nil
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Shortening

    var activeBackend: ShortenerBackend? {
        let credentials = ShortenerCredentials(
            accessToken: keychain.apiKey(for: settings.activeBackendID),
            defaultDomain: settings.backendDefaultDomain.isEmpty ? "bit.ly" : settings.backendDefaultDomain,
            defaultGroupGUID: settings.backendGroupGUID,
            defaultTags: settings.runtimeDefaultTags,
            session: .shared,
            cache: store
        )
        return registry.makeBackend(id: settings.activeBackendID, credentials: credentials)
    }

    var isBackendConfigured: Bool {
        activeBackend?.isConfigured ?? false
    }

    func beginShortening(_ item: ClipboardItem) {
        guard let url = item.url else {
            showToast("Only links can be shortened")
            return
        }
        guard isBackendConfigured else {
            showToast("Add a Bitly access token in Settings → Integrations")
            return
        }
        shortenRequest = ShortenRequest(item: item, url: url)
    }

    /// Returns an error message on failure, nil on success.
    func shorten(
        item: ClipboardItem,
        url: URL,
        slug: String?,
        domain: String?,
        tags: [String]
    ) async -> String? {
        guard let backend = activeBackend else {
            return "No shortening backend is configured."
        }
        isShortening = true
        defer { isShortening = false }

        do {
            let link = try await backend.createLink(
                destinationURL: url,
                domain: domain,
                slug: slug,
                tags: tags
            )
            if let itemID = item.id {
                try store.setShortURL(link.shortUrl, for: itemID)
            }
            insertShortLinkHistoryItem(link)
            recentShortLinks = try store.cachedShortLinks(limit: 50)
            pasteEngine.copyText(link.shortUrl)
            reload()
            shortenRequest = nil
            showToast("Shortened — \(link.shortUrl) copied")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func handleAutoShorten(_ item: ClipboardItem, _ rule: ShortenRule) {
        guard let url = item.url else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let backend = self.activeBackend, backend.isConfigured else { return }
            do {
                let slug: String? = rule.slugTemplate.flatMap { template in
                    let rendered = ShortenRulesEngine.renderSlug(template: template, url: url)
                    return rendered.isEmpty ? nil : rendered
                }
                let link = try await backend.createLink(
                    destinationURL: url,
                    domain: rule.domain,
                    slug: slug,
                    tags: []
                )
                if let itemID = item.id {
                    try? self.store.setShortURL(link.shortUrl, for: itemID)
                }
                self.insertShortLinkHistoryItem(link)
                if rule.autoCopy {
                    self.pasteEngine.copyText(link.shortUrl)
                }
                self.recentShortLinks = (try? self.store.cachedShortLinks(limit: 50)) ?? []
                self.reload()
                self.showToast(
                    rule.autoCopy
                        ? "Auto-shortened & copied: \(link.shortUrl)"
                        : "Auto-shortened: \(link.shortUrl)"
                )
            } catch {
                self.showToast("Auto-shorten failed: \(error.localizedDescription)")
            }
        }
    }

    /// The short URL becomes its own history item, so it can be searched,
    /// pinned or QR'd later like any other copy.
    private func insertShortLinkHistoryItem(_ link: ShortLink) {
        let hash = ClipboardPayloadReader.hash(kind: .url, strings: [link.shortUrl])
        _ = try? store.insert(
            kind: .url,
            text: link.shortUrl,
            title: link.title ?? link.destinationUrl,
            sourceApp: "Clipshot",
            bundleId: "com.ernest.clipshot",
            hash: hash
        )
    }

    func verifyBackend() async {
        guard let backend = activeBackend else { return }
        isVerifyingBackend = true
        credentialResult = await backend.verifyCredentials()
        isVerifyingBackend = false
    }

    /// Fetches the all-time click timeline for a cached Bitlink and updates the
    /// local cache, which drives the Recent Links menu.
    func refreshClicks(for link: ShortLink) async {
        guard let backend = activeBackend else { return }
        guard backend.capabilities.supportsClickStats else {
            showToast("This backend does not provide click analytics")
            return
        }

        refreshingClickLinkID = link.id
        defer { refreshingClickLinkID = nil }

        do {
            let stats = try await backend.clickStats(for: link.id)
            recentShortLinks = try store.cachedShortLinks(limit: 50)
            showToast("\(stats.totalClicks) click\(stats.totalClicks == 1 ? "" : "s") — \(link.shortUrl)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteCachedLink(_ link: ShortLink) {
        do {
            try store.deleteShortLink(id: link.id)
            recentShortLinks = try store.cachedShortLinks(limit: 50)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearPreviewCache() {
        linkPreviews.clearCache()
        showToast("Link preview cache cleared")
    }

    // MARK: - QR

    func showQR(for item: ClipboardItem, preferShort: Bool = true) {
        guard item.kind != .color else {
            showToast("Color swatches do not need a QR code")
            return
        }
        let shortUrl = item.shortUrl.flatMap { $0.isEmpty ? nil : $0 }
        let value = preferShort ? (shortUrl ?? item.text) : (item.text ?? shortUrl)
        guard let value, !value.isEmpty else {
            showToast("Nothing to encode")
            return
        }
        qrWindowController.show(value: value, title: item.displayText)
    }

    func showQRSelected() {
        guard let item = selectedItem else { return }
        showQR(for: item)
    }

    // MARK: - Privacy / permissions

    func pause(for duration: TimeInterval) {
        privacyFilter.pause(for: duration)
        isPaused = privacyFilter.isPaused
        linkPreviews.setPaused(true)
        showToast("Capture paused for \(Int(duration / 60)) min")
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isPaused = self.privacyFilter.isPaused
            if !self.isPaused {
                self.linkPreviews.setPaused(false)
            }
        }
    }

    func resumeCapture() {
        privacyFilter.resume()
        isPaused = false
        linkPreviews.setPaused(false)
        pauseTask?.cancel()
        showToast("Capture resumed")
    }

    func refreshAccessibility() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
    }

    func requestAccessibility() {
        AccessibilityPermission.prompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshAccessibility()
        }
    }

    // MARK: - Hotkeys

    func applyHotkeys() {
        hotkeyManager.unregisterAll()
        hotkeyError = nil
        for action in HotkeyAction.allCases {
            do {
                try hotkeyManager.register(settings.hotkey(for: action), for: action) { [weak self] in
                    self?.performHotkey(action)
                }
            } catch {
                hotkeyError = error.localizedDescription
            }
        }
    }

    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        settings.setHotkey(hotkey, for: action)
        applyHotkeys()
    }

    func resetHotkey(for action: HotkeyAction) {
        settings.resetHotkey(for: action)
        applyHotkeys()
    }

    private func performHotkey(_ action: HotkeyAction) {
        switch action {
        case .toggleOverlay:
            overlayController.toggle()
        case .shorten:
            if overlayController.isVisible, let item = selectedItem {
                beginShortening(item)
            } else {
                overlayController.show()
            }
        case .showQR:
            if overlayController.isVisible, selectedItem != nil {
                showQRSelected()
            } else {
                let recent = recentShortLinks.first
                if let recent {
                    qrWindowController.show(value: recent.shortUrl, title: recent.shortUrl)
                } else {
                    overlayController.show()
                }
            }
        }
    }

    // MARK: - Overlay keyboard

    /// Returns true when the event was consumed by the overlay.
    func handleOverlayKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        if keyCode == kVK_Escape {
            overlayController.hide()
            return true
        }

        if flags.contains(.command), let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), digit >= 1, digit <= 9 {
            quickPaste(index: digit - 1)
            return true
        }

        if flags.contains(.command) {
            switch keyCode {
            case kVK_ANSI_N:
                beginNewSnippet()
                return true
            case kVK_ANSI_E:
                if let item = selectedItem { beginEdit(item) }
                return true
            case kVK_ANSI_R:
                if let item = selectedItem { beginRename(item) }
                return true
            case kVK_ANSI_P:
                if let item = selectedItem { togglePin(item) }
                return true
            case kVK_ANSI_K:
                if let item = selectedItem { beginShortening(item) }
                return true
            default:
                return false
            }
        }

        if flags.contains(.option), flags.contains(.shift) {
            switch keyCode {
            case kVK_ANSI_S:
                if let item = selectedItem { beginShortening(item) }
                return true
            case kVK_ANSI_Q:
                showQRSelected()
                return true
            default:
                return false
            }
        }

        switch keyCode {
        case kVK_LeftArrow:
            moveSelection(by: -1)
            return true
        case kVK_RightArrow:
            moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected(plainText: flags.contains(.shift))
            return true
        case kVK_Space:
            if let item = selectedItem { quickLook.preview(item, dataStore: dataStore) }
            return true
        case kVK_Delete:
            if let item = selectedItem { delete(item) }
            return true
        default:
            return false
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
