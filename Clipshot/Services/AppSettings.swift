import Foundation

enum EditorMode: String, Identifiable {
    case newSnippet
    case newLink
    case editText
    case rename

    var id: String { rawValue }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let mode: EditorMode
    let item: ClipboardItem?
}

struct ShortenRequest: Identifiable {
    let id = UUID()
    let item: ClipboardItem
    let url: URL
}

struct PinboardRenameRequest: Identifiable {
    let id = UUID()
    let pinboard: Pinboard
}

/// UserDefaults-backed settings. Everything here is local; API keys live in Keychain.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) } }
    @Published var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) } }
    @Published var overlayHeight: Double { didSet { defaults.set(overlayHeight, forKey: Keys.overlayHeight) } }
    @Published var alwaysCompact: Bool { didSet { defaults.set(alwaysCompact, forKey: Keys.alwaysCompact) } }
    @Published var preferShortLinks: Bool { didSet { defaults.set(preferShortLinks, forKey: Keys.preferShortLinks) } }
    @Published var fetchLinkPreviews: Bool { didSet { defaults.set(fetchLinkPreviews, forKey: Keys.fetchLinkPreviews) } }
    @Published var skipTransient: Bool { didSet { defaults.set(skipTransient, forKey: Keys.skipTransient) } }
    @Published var skipConcealed: Bool { didSet { defaults.set(skipConcealed, forKey: Keys.skipConcealed) } }
    @Published var ignoredBundleIds: [String] { didSet { defaults.set(ignoredBundleIds, forKey: Keys.ignoredBundleIds) } }
    @Published var activeBackendID: String { didSet { defaults.set(activeBackendID, forKey: Keys.activeBackendID) } }
    @Published var backendDefaultDomain: String { didSet { defaults.set(backendDefaultDomain, forKey: Keys.backendDefaultDomain) } }
    @Published var backendGroupGUID: String { didSet { defaults.set(backendGroupGUID, forKey: Keys.backendGroupGUID) } }
    @Published var backendDefaultTags: String { didSet { defaults.set(backendDefaultTags, forKey: Keys.backendDefaultTags) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }
    @Published var warnWhenPasteRunning: Bool { didSet { defaults.set(warnWhenPasteRunning, forKey: Keys.warnWhenPasteRunning) } }
    @Published var mcpEnabled: Bool { didSet { defaults.set(mcpEnabled, forKey: Keys.mcpEnabled) } }
    @Published var mcpToken: String { didSet { defaults.set(mcpToken, forKey: Keys.mcpToken) } }
    /// Actual URL of the running server. Runtime-only: the bound port is only
    /// known after the listener starts, so it is never persisted.
    @Published var mcpURL: String?

    private var hotkeys: [String: Hotkey]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 0
        self.showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.overlayHeight = defaults.object(forKey: Keys.overlayHeight) as? Double ?? 460
        self.alwaysCompact = defaults.bool(forKey: Keys.alwaysCompact)
        self.preferShortLinks = defaults.object(forKey: Keys.preferShortLinks) as? Bool ?? true
        self.fetchLinkPreviews = defaults.object(forKey: Keys.fetchLinkPreviews) as? Bool ?? true
        self.skipTransient = defaults.object(forKey: Keys.skipTransient) as? Bool ?? true
        self.skipConcealed = defaults.object(forKey: Keys.skipConcealed) as? Bool ?? true
        self.ignoredBundleIds = defaults.stringArray(forKey: Keys.ignoredBundleIds)
            ?? Array(PrivacyFilterConfiguration.defaultIgnoredBundleIds).sorted()
        let storedBackendID = defaults.string(forKey: Keys.activeBackendID)
        // Migrate the pre-Bitly provider id.
        if storedBackendID == "shortmenu" || storedBackendID == nil {
            self.activeBackendID = BitlyBackend.backendIdentifier
        } else {
            self.activeBackendID = storedBackendID!
        }
        self.backendDefaultDomain = {
            let stored = defaults.string(forKey: Keys.backendDefaultDomain)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty, stored != "shm.to" {
                return stored
            }
            return "bit.ly"
        }()
        self.backendGroupGUID = defaults.string(forKey: Keys.backendGroupGUID) ?? ""
        self.backendDefaultTags = defaults.string(forKey: Keys.backendDefaultTags) ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.warnWhenPasteRunning = defaults.object(forKey: Keys.warnWhenPasteRunning) as? Bool ?? true
        self.mcpEnabled = defaults.object(forKey: Keys.mcpEnabled) as? Bool ?? false
        self.mcpToken = defaults.string(forKey: Keys.mcpToken) ?? ""
        self.mcpURL = nil

        var stored: [String: Hotkey] = [:]
        if let data = defaults.data(forKey: Keys.hotkeys),
           let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            stored = decoded
        }
        self.hotkeys = stored
    }

    var runtimeDefaultTags: [String] {
        backendDefaultTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func hotkey(for action: HotkeyAction) -> Hotkey {
        hotkeys[action.rawValue] ?? action.defaultHotkey
    }

    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        hotkeys[action.rawValue] = hotkey
        persistHotkeys()
    }

    func resetHotkeys() {
        hotkeys.removeAll()
        persistHotkeys()
    }

    func resetHotkey(for action: HotkeyAction) {
        hotkeys.removeValue(forKey: action.rawValue)
        persistHotkeys()
    }

    var allHotkeys: [(action: HotkeyAction, hotkey: Hotkey)] {
        HotkeyAction.allCases.map { ($0, hotkey(for: $0)) }
    }

    func privacyConfiguration() -> PrivacyFilterConfiguration {
        PrivacyFilterConfiguration(
            ignoredBundleIds: Set(ignoredBundleIds),
            skipTransient: skipTransient,
            skipConcealed: skipConcealed
        )
    }

    private func persistHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) {
            defaults.set(data, forKey: Keys.hotkeys)
        }
    }

    private enum Keys {
        static let retentionDays = "settings.retentionDays"
        static let showDockIcon = "settings.showDockIcon"
        static let launchAtLogin = "settings.launchAtLogin"
        static let overlayHeight = "settings.overlayHeight"
        static let alwaysCompact = "settings.alwaysCompact"
        static let preferShortLinks = "settings.preferShortLinks"
        static let fetchLinkPreviews = "settings.fetchLinkPreviews"
        static let skipTransient = "settings.skipTransient"
        static let skipConcealed = "settings.skipConcealed"
        static let ignoredBundleIds = "settings.ignoredBundleIds"
        static let activeBackendID = "settings.activeBackendID"
        static let backendDefaultDomain = "settings.backendDefaultDomain"
        static let backendGroupGUID = "settings.backendGroupGUID"
        static let backendDefaultTags = "settings.backendDefaultTags"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let warnWhenPasteRunning = "settings.warnWhenPasteRunning"
        static let mcpEnabled = "settings.mcpEnabled"
        static let mcpToken = "settings.mcpToken"
        static let hotkeys = "settings.hotkeys"
    }
}
