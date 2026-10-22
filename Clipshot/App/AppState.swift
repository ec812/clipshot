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
    let ocrEngine: OCREngine
    let keychain: APIKeyStoring
    let registry: ShortenerBackendRegistry
    let monitor: ClipboardMonitor
    let mcpToolRouter: MCPToolRouter
    let hotkeyManager = HotkeyManager()
    let pasteStack = PasteStack()
    let qrWindowController = QRWindowController()
    let onboardingController = OnboardingWindowController()
    let quickLook = QuickLookPresenter()
    let appIcons = AppIconProvider()
    let linkPreviews = LinkPreviewStore()
    let clipImages = ClipImageStore()
    let codeHighlight = CodeHighlightStore()

    lazy var pasteEngine: PasteEngine = PasteEngine(
        noteOwnWrite: { [weak self] in self?.monitor.noteOwnWrite() }
    )

    lazy var overlayController: OverlayController = OverlayController(appState: self)

    @Published var items: [ClipboardItem] = []
    @Published var selectedItemID: Int64?
    /// Set by `reveal(_:)` when clearing a filter starts an asynchronous reload.
    /// The timeline re-centers this id after the reloaded items land, then
    /// acknowledges it. Without this, the selection scroll would run against
    /// the still-filtered list and the item could land off-center.
    @Published private(set) var revealTargetID: Int64?
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
    @Published var pinboardRenameRequest: PinboardRenameRequest?
    @Published var pasteStackCount = 0
    @Published private(set) var isSearchFieldFocused = false
    @Published private(set) var databaseError: String?
    @Published var mcpError: String?

    var isTesting: Bool
    private var startMonitoring: Bool
    private var started = false
    private var mcpServer: MCPServer?
    private var reloadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var distributedObserver: NSObjectProtocol?
    private var reloadGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        store: HistoryStore? = nil,
        settings: AppSettings? = nil,
        keychain: APIKeyStoring? = nil,
        startMonitoring: Bool = true,
        dataStore: ItemDataStore? = nil,
        ocrEngine: OCREngine = VisionOCREngine()
    ) {
        let resolvedSettings = settings ?? AppSettings()
        let resolvedKeychain = keychain ?? KeychainStore()

        let resolvedStore: HistoryStore
        var initialDatabaseError: String?
        if let store {
            resolvedStore = store
        } else {
            do {
                resolvedStore = try HistoryStore.openDefaultDatabase()
            } catch {
                let path = (try? HistoryStore.defaultDatabaseURL().path) ?? "unknown path"
                let message = "History database unavailable at \(path): \(error.localizedDescription). Using a temporary store; the database file was not deleted."
                NSLog("Clipshot: \(message)")
                resolvedStore = try! HistoryStore.inMemory()
                initialDatabaseError = message
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
        self.ocrEngine = ocrEngine
        self.keychain = resolvedKeychain
        self.registry = ShortenerBackendRegistry.shared
        self.startMonitoring = startMonitoring
        self.isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.databaseError = initialDatabaseError
        self.mcpToolRouter = MCPToolRouter(store: resolvedStore)

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
        refreshAccessibility()

        let store = self.store
        let retentionDays = settings.retentionDays
        Task.detached(priority: .userInitiated) {
            var migrated = false
            do {
                try store.migrateIfNeeded()
                _ = try? store.applyRetention(days: retentionDays)
                migrated = true
            } catch {
                let recovered = (try? store.recoverAfterIOError(error)) ?? false
                migrated = recovered
                await MainActor.run {
                    if recovered {
                        self.databaseError = nil
                    } else {
                        self.databaseError = "History database error: \(error.localizedDescription)"
                        self.lastError = error.localizedDescription
                    }
                }
            }
            let migrationReady = migrated
            await MainActor.run {
                self.reload()
                if self.startMonitoring {
                    self.monitor.start()
                }
                if !self.isTesting {
                    self.applyHotkeys()
                }
                if migrationReady, self.settings.mcpEnabled, !self.isTesting {
                    self.startMCP()
                }
                if !self.settings.hasCompletedOnboarding, !self.isTesting {
                    self.presentOnboarding()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility()
            }
        }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstanceGuard.showOverlayNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.overlayController.show()
            }
        }
    }

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    // MARK: - Local MCP

    func setMCPEnabled(_ enabled: Bool) {
        if enabled, settings.mcpToken.isEmpty {
            settings.mcpToken = UUID().uuidString
        }
        settings.mcpEnabled = enabled
        if enabled {
            startMCP()
        } else {
            stopMCP()
        }
    }

    func startMCP() {
        guard mcpServer == nil, settings.mcpEnabled, !settings.mcpToken.isEmpty else { return }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let router = mcpToolRouter
        let handler = MCPProtocol(
            serverVersion: version ?? "1.0",
            tools: router.tools,
            toolHandler: { name, arguments in
                router.call(name, arguments: arguments)
            }
        )
        let server = MCPServer(protocolHandler: handler)
        mcpServer = server
        mcpError = nil

        server.start(token: settings.mcpToken, preferredPort: MCPServer.defaultPort) { [weak self] result in
            Task { @MainActor in
                guard let self, self.mcpServer === server else { return }
                switch result {
                case .success(let port):
                    self.settings.mcpURL = "http://127.0.0.1:\(port)\(MCPServer.path)"
                    self.mcpError = nil
                case .failure(let error):
                    self.mcpServer = nil
                    self.settings.mcpURL = nil
                    self.mcpError = error.localizedDescription
                }
            }
        }
    }

    func stopMCP() {
        mcpServer?.stop()
        mcpServer = nil
        settings.mcpURL = nil
        mcpError = nil
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

    /// Applies the filter chips and the typed search-bar syntax together: they
    /// always intersect (AND). Typed `kind:`/`from:`/`date:`/`pinboard:` clauses
    /// narrow the chip selection instead of replacing it, so a contradiction such
    /// as chip = Link plus `kind:text` intentionally yields no results.
    ///
    /// Both states stay in effect; whichever one wrote last (through the `didSet`
    /// handlers above) drives this reload.
    func reload() {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let query = searchText
        let kind = filterKind
        let bundleId = filterBundleId
        let pinnedOnly = filterPinnedOnly
        let pinboardID = filterPinboardID
        let parsed = SearchQueryParser.parse(query)
        let now = Date()

        var freeText = parsed.freeText
        var parsedPinboardID: Int64?
        if let name = parsed.pinboardName {
            if let board = pinboards.first(where: {
                $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
            }) {
                parsedPinboardID = board.id
            } else {
                // Unknown pinboard name: keep the words searchable rather than
                // silently hiding every row.
                freeText = [freeText, name]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }

        let dateInterval = parsed.dateFilter?.interval(now: now)
        let kindConflict = kind != nil && parsed.kind != nil && kind != parsed.kind
        let pinboardConflict = pinboardID != nil
            && parsedPinboardID != nil
            && pinboardID != parsedPinboardID
        let effectiveKind = kind ?? parsed.kind
        let effectivePinboardID = pinboardID ?? parsedPinboardID
        let store = self.store

        Task.detached(priority: .userInitiated) {
            do {
                let results: [ClipboardItem]
                if kindConflict || pinboardConflict {
                    results = []
                } else {
                    results = try store.search(
                        freeText,
                        kind: effectiveKind,
                        bundleId: bundleId,
                        sourceAppOrBundleId: parsed.fromApp,
                        createdAtFrom: dateInterval?.start,
                        createdAtTo: dateInterval?.end,
                        phrase: parsed.phrase
                    )
                }
                let loaded = results.filter { item in
                    if pinnedOnly && !item.isPinned { return false }
                    if let effectivePinboardID, item.pinboardId != effectivePinboardID {
                        return false
                    }
                    return true
                }
                let sources = try store.distinctSources()
                let boards = try store.pinboards()
                let rules = try store.shortenRules()
                let links = try store.cachedShortLinks(limit: 50)

                await MainActor.run { [weak self] in
                    guard let self, generation == self.reloadGeneration else { return }
                    self.items = loaded
                    if self.selectedItemID == nil
                        || !loaded.contains(where: { $0.id == self.selectedItemID }) {
                        self.selectedItemID = loaded.first?.id
                    }
                    self.sourceApps = sources
                    self.pinboards = boards
                    self.rules = rules
                    self.recentShortLinks = links
                }
            } catch {
                let recovered = (try? store.recoverAfterIOError(error)) ?? false
                if recovered {
                    await MainActor.run { [weak self] in
                        self?.databaseError = nil
                        self?.reload()
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.databaseError = "History database error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Runs a store mutation away from the main actor, then refreshes the UI.
    private func performStoreWrite(
        _ operation: @escaping (HistoryStore) throws -> Void,
        completion: @escaping () -> Void = {}
    ) {
        let store = self.store
        Task.detached(priority: .userInitiated) {
            do {
                do {
                    try operation(store)
                } catch {
                    guard (try? store.recoverAfterIOError(error)) == true else {
                        throw error
                    }
                    try operation(store)
                }
                await MainActor.run { [weak self] in
                    self?.databaseError = nil
                    completion()
                    self?.reload()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.databaseError = "History database error: \(error.localizedDescription)"
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    /// True when the timeline is narrowed by a search query or any filter.
    var hasActiveFilter: Bool {
        !searchText.isEmpty
            || filterKind != nil
            || filterBundleId != nil
            || filterPinnedOnly
            || filterPinboardID != nil
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

    /// Clears the search query and any filter that would hide `item`, then
    /// selects it so the timeline's selection scroll centers it in the
    /// unfiltered history.
    ///
    /// Reveal semantics:
    /// 1. Clear `searchText`.
    /// 2. Clear `filterKind`, `filterBundleId`, `filterPinnedOnly`.
    /// 3. Keep `filterPinboardID` when it already shows the item; otherwise
    ///    point it at the item's own board (or clear it when the item has none).
    /// 4. Select the item last. Clearing a filter reloads asynchronously, so the
    ///    selection is set before that reload publishes; `reload()` keeps it
    ///    because the reloaded (unfiltered) set contains the item.
    func reveal(_ item: ClipboardItem) {
        var reloadStarted = false

        if !searchText.isEmpty {
            searchText = ""
            reloadStarted = true
        }
        if filterKind != nil {
            filterKind = nil
            reloadStarted = true
        }
        if filterBundleId != nil {
            filterBundleId = nil
            reloadStarted = true
        }
        if filterPinnedOnly {
            filterPinnedOnly = false
            reloadStarted = true
        }
        if let board = filterPinboardID, board != item.pinboardId {
            filterPinboardID = item.pinboardId
            reloadStarted = true
        }

        // The selection is set immediately, but a reload is already in flight.
        // Remember the target so the timeline can re-center once the unfiltered
        // items replace the filtered ones.
        if reloadStarted, let id = item.id {
            revealTargetID = id
        }
        selectedItemID = item.id
    }

    /// Called by the timeline after it re-centers a reveal target.
    func acknowledgeReveal() {
        revealTargetID = nil
    }

    private func handleCaptured(_ item: ClipboardItem) {
        guard overlayController.isVisible else { return }

        // The monitor has already committed the item. For the common unfiltered
        // view, publish it immediately instead of waiting for a DB re-query.
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           filterKind == nil || filterKind == item.kind,
           filterBundleId == nil || filterBundleId == item.bundleId,
           !filterPinnedOnly || item.isPinned,
           filterPinboardID == nil || filterPinboardID == item.pinboardId {
            // Discard any reload that started before this insert; otherwise its
            // pre-insert snapshot can overwrite the item we are publishing now.
            reloadGeneration &+= 1
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
            // Select the new item so the timeline scrolls it into view; otherwise
            // a capture can be published off-screen while an older card is selected.
            selectedItemID = item.id
        } else {
            reload()
        }
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        let override = preferredText(for: item, preferShort: false)
        Task { [weak self] in
            guard let self else { return }
            await self.pasteEngine.copyToClipboard(item, textOverride: override)
            self.showToast("Copied")
        }
    }

    func paste(_ item: ClipboardItem, plainText: Bool = false) {
        let override = preferredText(for: item, preferShort: false)
        overlayController.hide()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.pasteEngine.paste(
                item,
                plainText: plainText,
                textOverride: override
            )
            switch outcome {
            case .pasted:
                break
            case .copiedToClipboard:
                self.showToast("Copied — Accessibility permission is needed to paste directly")
            case .failed(let message):
                self.showToast(message)
            }
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
        item.pasteTextOverride(preferShort: preferShort)
    }

    func copyToClipboard(_ string: String) {
        pasteEngine.copyText(string)
        showToast("Copied \(string)")
    }

    func togglePin(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        let pinned = !item.isPinned
        performStoreWrite({ store in
            try store.setPinned(pinned, for: id)
        }, completion: { [weak self] in
            self?.showToast(pinned ? "Pinned" : "Unpinned")
        })
    }

    func addToPinboard(_ item: ClipboardItem, pinboard: Pinboard) {
        guard let itemID = item.id, let pinboardID = pinboard.id else { return }
        let pinboardName = pinboard.name
        performStoreWrite({ store in
            try store.addItem(itemID, toPinboard: pinboardID)
        }, completion: { [weak self] in
            self?.showToast("Added to \(pinboardName)")
        })
    }

    func removeFromPinboard(_ item: ClipboardItem) {
        guard let itemID = item.id else { return }
        performStoreWrite({ store in
            try store.removeItemFromPinboard(itemID)
        })
    }

    func delete(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        let dataStore = self.dataStore
        let path = item.dataPath
        performStoreWrite({ store in
            if let path {
                dataStore.delete(atPath: path)
            }
            try store.deleteItem(id: id)
        })
    }

    // MARK: - OCR

    func extractTextFromImage(_ item: ClipboardItem) {
        guard item.kind == .image, let itemID = item.id, let path = item.dataPath else {
            showToast("Only images can be read")
            return
        }

        let store = self.store
        let engine = ocrEngine
        let url = URL(fileURLWithPath: path)

        Task { [weak self] in
            guard let self else { return }
            do {
                let recognized = try await engine.recognizeText(inImageAt: url)
                let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.showToast("No text found")
                    return
                }
                try await Task.detached(priority: .userInitiated) {
                    try store.updateOcrText(text, for: itemID)
                }.value
                self.reload()
                self.pasteEngine.copyText(text)
                self.showToast("Text extracted")
            } catch {
                self.showToast("Could not extract text")
            }
        }
    }

    func createPinboard(name: String, colorHex: String) {
        performStoreWrite({ store in
            _ = try store.createPinboard(name: name, colorHex: colorHex)
        }, completion: { [weak self] in
            self?.showToast("Pinboard created")
        })
    }

    func beginRenamePinboard(_ pinboard: Pinboard) {
        pinboardRenameRequest = PinboardRenameRequest(pinboard: pinboard)
    }

    func renamePinboard(_ pinboard: Pinboard, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = pinboard.id else { return }
        performStoreWrite({ store in
            try store.renamePinboard(id: id, name: trimmed)
        }, completion: { [weak self] in
            self?.pinboardRenameRequest = nil
            self?.showToast("Pinboard renamed")
        })
    }

    func deletePinboard(_ pinboard: Pinboard) {
        guard let id = pinboard.id else { return }
        let shouldClearFilter = filterPinboardID == id
        performStoreWrite({ store in
            try store.deletePinboard(id: id)
        }, completion: { [weak self] in
            if shouldClearFilter {
                self?.filterPinboardID = nil
            }
        })
    }

    // MARK: - Auto-shorten rules

    func saveRule(_ rule: ShortenRule) {
        performStoreWrite({ store in
            _ = try store.saveShortenRule(rule)
        })
    }

    func deleteRule(_ rule: ShortenRule) {
        guard let id = rule.id else { return }
        performStoreWrite({ store in
            try store.deleteShortenRule(id: id)
        })
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
        Task { [weak self] in
            _ = await self?.pasteEngine.paste(next, plainText: false, textOverride: override)
        }
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
        guard request.mode != .newSnippet
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        performStoreWrite({ store in
            switch request.mode {
            case .newSnippet:
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
                guard let id = request.item?.id else { return }
                try store.updateText(text, title: trimmedTitle.isEmpty ? nil : trimmedTitle, for: id)
            case .rename:
                guard let id = request.item?.id else { return }
                try store.rename(trimmedTitle, for: id)
            }
        }, completion: { [weak self] in
            self?.editorRequest = nil
        })
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
            let store = self.store
            let itemID = item.id
            let links = try await Task.detached(priority: .userInitiated) { () -> [ShortLink] in
                if let itemID {
                    try store.setShortURL(link.shortUrl, for: itemID)
                }
                let hash = ClipboardPayloadReader.hash(kind: .url, strings: [link.shortUrl])
                _ = try? store.insert(
                    kind: .url,
                    text: link.shortUrl,
                    title: link.title ?? link.destinationUrl,
                    sourceApp: "Clipshot",
                    bundleId: "com.ernest.clipshot",
                    hash: hash
                )
                return try store.cachedShortLinks(limit: 50)
            }.value
            recentShortLinks = links
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
                let store = self.store
                let itemID = item.id
                let links = try await Task.detached(priority: .userInitiated) { () -> [ShortLink] in
                    if let itemID {
                        try store.setShortURL(link.shortUrl, for: itemID)
                    }
                    let hash = ClipboardPayloadReader.hash(kind: .url, strings: [link.shortUrl])
                    _ = try? store.insert(
                        kind: .url,
                        text: link.shortUrl,
                        title: link.title ?? link.destinationUrl,
                        sourceApp: "Clipshot",
                        bundleId: "com.ernest.clipshot",
                        hash: hash
                    )
                    return try store.cachedShortLinks(limit: 50)
                }.value
                if rule.autoCopy {
                    self.pasteEngine.copyText(link.shortUrl)
                }
                self.recentShortLinks = links
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
            let store = self.store
            let links = (try? await Task.detached(priority: .utility) {
                try store.cachedShortLinks(limit: 50)
            }.value) ?? []
            recentShortLinks = links
            showToast("\(stats.totalClicks) click\(stats.totalClicks == 1 ? "" : "s") — \(link.shortUrl)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteCachedLink(_ link: ShortLink) {
        performStoreWrite({ store in
            try store.deleteShortLink(id: link.id)
        })
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
                NSLog("Clipshot: registered hotkey \(action.rawValue) = \(settings.hotkey(for: action).displayString)")
            } catch {
                hotkeyError = error.localizedDescription
                NSLog("Clipshot: hotkey registration FAILED for \(action.rawValue): \(error.localizedDescription)")
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
        let editingSearch = isSearchFieldFocused || isTextInputFocused(event)

        if keyCode == kVK_Escape {
            overlayController.hide()
            return true
        }

        // While editing a non-empty query, arrows move the insertion point.
        // With an empty query there is no caret to move, so they navigate cards.
        if editingSearch, !searchText.isEmpty,
           keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow {
            return false
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
            case kVK_ANSI_Y:
                if let item = selectedItem { quickLook.preview(item, dataStore: dataStore) }
                return true
            case kVK_Delete:
                // Command-Backspace always deletes the selected item, even while
                // the search field has focus.
                if let item = selectedItem { delete(item) }
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
            // While editing the search field, Space must type a space.
            if editingSearch { return false }
            if let item = selectedItem { quickLook.preview(item, dataStore: dataStore) }
            return true
        case kVK_Delete:
            // While editing the search field, Backspace must edit the query.
            // Use ⌘⌫ to delete a history item.
            if editingSearch { return false }
            if let item = selectedItem { delete(item) }
            return true
        default:
            return false
        }
    }

    func setSearchFieldFocused(_ focused: Bool) {
        isSearchFieldFocused = focused
    }

    private func isTextInputFocused(_ event: NSEvent) -> Bool {
        let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder
        guard let responder else { return false }
        if responder is NSTextView || responder is NSTextField || responder is NSText {
            return true
        }
        return responder is NSTextInputClient
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
