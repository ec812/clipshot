import AppKit
import Foundation

/// Polls `NSPasteboard.changeCount` on the main run loop.
///
/// Polling is intentional: changeCount is cheap, does not require extra TCC
/// permissions, and matches the approach used by other clipboard managers.
@MainActor
final class ClipboardMonitor {
    var onCapture: ((ClipboardItem) -> Void)?
    var onAutoShorten: ((ClipboardItem, ShortenRule) -> Void)?

    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let privacyFilter: PrivacyFilter
    private let rulesEngine: ShortenRulesEngine
    private let dataStore: ItemDataStore
    private let pollInterval: TimeInterval

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCounts: Set<Int> = []
    private var lastHash: String?

    init(
        store: HistoryStore,
        privacyFilter: PrivacyFilter,
        rulesEngine: ShortenRulesEngine,
        dataStore: ItemDataStore,
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.3
    ) {
        self.store = store
        self.privacyFilter = privacyFilter
        self.rulesEngine = rulesEngine
        self.dataStore = dataStore
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call immediately after the app writes to the pasteboard itself so the
    /// write is not captured back into history.
    func noteOwnWrite() {
        ignoredChangeCounts.insert(pasteboard.changeCount)
        if ignoredChangeCounts.count > 20 {
            ignoredChangeCounts.remove(ignoredChangeCounts.min() ?? 0)
        }
        lastChangeCount = pasteboard.changeCount
    }

    /// Forces the next poll to treat the current pasteboard as new.
    func resetBaseline() {
        lastChangeCount = pasteboard.changeCount
        lastHash = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if ignoredChangeCounts.contains(changeCount) {
            ignoredChangeCounts.remove(changeCount)
            return
        }

        guard !privacyFilter.isPaused else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleId = frontmost?.bundleIdentifier
        let sourceApp = frontmost?.localizedName
        let types = Set((pasteboard.types ?? []).map(\.rawValue))

        guard privacyFilter.shouldCapture(
            bundleId: bundleId,
            pasteboardTypes: types,
            sourceApp: sourceApp
        ) else { return }

        guard let payload = ClipboardPayloadReader.read(from: pasteboard, dataStore: dataStore) else {
            return
        }
        guard payload.hash != lastHash else { return }
        lastHash = payload.hash

        do {
            let outcome = try store.insert(
                kind: payload.kind,
                text: payload.text,
                title: payload.title,
                dataPath: payload.dataPath,
                sourceApp: sourceApp,
                bundleId: bundleId,
                hash: payload.hash
            )
            onCapture?(outcome.item)

            guard outcome.wasInserted, let url = outcome.item.url else { return }
            let context = ShortenRuleContext(
                url: url,
                sourceApp: sourceApp,
                bundleId: bundleId,
                date: Date()
            )
            if let rule = try rulesEngine.matchingRule(for: context) {
                onAutoShorten?(outcome.item, rule)
            }
        } catch {
            NSLog("Clipshot: failed to capture clipboard item: \(error)")
        }
    }
}
