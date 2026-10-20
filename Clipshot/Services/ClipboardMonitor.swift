import AppKit
import Foundation

/// Polls `NSPasteboard.changeCount` on the main run loop.
///
/// Polling is intentional: changeCount is cheap, does not require extra TCC
/// permissions, and matches the approach used by other clipboard managers.
/// Only the pasteboard snapshot happens on the main thread; hashing, image/RTF
/// persistence, database inserts, and rule evaluation run on a serial queue.
final class ClipboardMonitor {
    var onCapture: ((ClipboardItem) -> Void)?
    var onAutoShorten: ((ClipboardItem, ShortenRule) -> Void)?

    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let privacyFilter: PrivacyFilter
    private let rulesEngine: ShortenRulesEngine
    private let dataStore: ItemDataStore
    private let pollInterval: TimeInterval
    private let processingQueue = DispatchQueue(
        label: "com.ernest.clipshot.clipboard-capture",
        qos: .utility
    )

    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var lastChangeCount: Int
    private var ignoredChangeCounts: Set<Int> = []
    /// Only touched on `processingQueue`.
    private var lastHash: String?

    init(
        store: HistoryStore,
        privacyFilter: PrivacyFilter,
        rulesEngine: ShortenRulesEngine,
        dataStore: ItemDataStore,
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.1
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
        // Keep App Nap from throttling the 10 Hz polling timer while Clipshot is
        // in the background; otherwise copies can appear seconds late.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Capture clipboard changes promptly"
        )
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
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
        processingQueue.async { [weak self] in
            self?.lastHash = nil
        }
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

        guard let snapshot = ClipboardPayloadReader.snapshot(from: pasteboard) else {
            return
        }

        processingQueue.async { [weak self] in
            self?.process(
                snapshot,
                bundleId: bundleId,
                sourceApp: sourceApp
            )
        }
    }

    private func process(
        _ snapshot: PasteboardCaptureSnapshot,
        bundleId: String?,
        sourceApp: String?
    ) {
        guard let payload = ClipboardPayloadReader.process(snapshot, dataStore: dataStore) else {
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
            DispatchQueue.main.async { [weak self] in
                self?.onCapture?(outcome.item)
            }

            guard outcome.wasInserted, let url = outcome.item.url else { return }
            let context = ShortenRuleContext(
                url: url,
                sourceApp: sourceApp,
                bundleId: bundleId,
                date: Date()
            )
            if let rule = try rulesEngine.matchingRule(for: context) {
                DispatchQueue.main.async { [weak self] in
                    self?.onAutoShorten?(outcome.item, rule)
                }
            }
        } catch {
            NSLog("Clipshot: failed to capture clipboard item: \(error)")
        }
    }
}
