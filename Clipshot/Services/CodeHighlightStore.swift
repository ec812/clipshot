import Combine
import Foundation
import SwiftUI

private let codeHighlightBackgroundScheduler: CodeHighlightStore.Scheduler = { work in
    Task.detached(priority: .utility) { work() }
}

@MainActor
final class CodeHighlightStore: ObservableObject {
    typealias Detector = @Sendable (String) -> CodeLanguage?
    typealias Highlighter = @Sendable (String, CodeLanguage, ColorScheme) -> AttributedString
    typealias Scheduler = @Sendable (@escaping @Sendable () -> Void) -> Void

    static let overridesKey = "codeHighlightOverrides"
    static let maxOverrides = 500

    struct Result {
        let language: CodeLanguage?
        let light: AttributedString?
        let dark: AttributedString?
    }

    @Published private(set) var revision = 0

    private var results: [String: Result] = [:]
    private var inFlight: [String: UUID] = [:]
    private var overrides: [String: Bool] = [:]

    private let defaults: UserDefaults
    private let detect: Detector
    private let highlight: Highlighter
    private let scheduler: Scheduler

    init(
        defaults: UserDefaults = .standard,
        detect: @escaping Detector = { CodeDetector.detect($0) },
        highlight: @escaping Highlighter = {
            CodeHighlighter.attributedPreview($0, language: $1, colorScheme: $2)
        },
        scheduler: @escaping Scheduler = codeHighlightBackgroundScheduler
    ) {
        self.defaults = defaults
        self.detect = detect
        self.highlight = highlight
        self.scheduler = scheduler
        if let stored = defaults.dictionary(forKey: Self.overridesKey) as? [String: Bool] {
            overrides = stored
        }
    }

    func attributedPreview(
        for item: ClipboardItem,
        colorScheme: ColorScheme
    ) -> AttributedString? {
        guard item.kind == .text else { return nil }
        if overrides[item.hash] == false { return nil }
        guard let result = results[item.hash], result.language != nil else {
            return nil
        }
        return colorScheme == .dark ? result.dark : result.light
    }

    func isCode(for item: ClipboardItem) -> Bool {
        guard item.kind == .text else { return false }
        if let override = overrides[item.hash] { return override }
        return results[item.hash]?.language != nil
    }

    func ensureProcessed(_ item: ClipboardItem) {
        guard item.kind == .text, let text = item.text, !text.isEmpty else { return }
        guard results[item.hash] == nil, inFlight[item.hash] == nil else { return }
        startProcessing(
            item: item,
            text: text,
            forceCode: overrides[item.hash] == true
        )
    }

    func setOverride(_ value: Bool?, for item: ClipboardItem) {
        guard item.kind == .text else { return }
        if let value {
            overrides[item.hash] = value
        } else {
            overrides.removeValue(forKey: item.hash)
        }
        persistOverrides()

        results.removeValue(forKey: item.hash)
        inFlight.removeValue(forKey: item.hash)
        revision += 1

        if let text = item.text, !text.isEmpty {
            startProcessing(
                item: item,
                text: text,
                forceCode: value == true
            )
        }
    }

    private func startProcessing(
        item: ClipboardItem,
        text: String,
        forceCode: Bool
    ) {
        let hash = item.hash
        guard inFlight[hash] == nil else { return }

        let generation = UUID()
        inFlight[hash] = generation
        let detect = self.detect
        let highlight = self.highlight

        scheduler { [weak self] in
            let result = Self.process(
                text: text,
                forceCode: forceCode,
                detect: detect,
                highlight: highlight
            )
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.finish(hash: hash, generation: generation, result: result)
                }
            } else {
                Task { @MainActor in
                    self.finish(hash: hash, generation: generation, result: result)
                }
            }
        }
    }

    nonisolated private static func process(
        text: String,
        forceCode: Bool,
        detect: Detector,
        highlight: Highlighter
    ) -> Result {
        let detected = detect(text)
        let language = forceCode ? (detected ?? .generic) : detected
        guard let language else {
            return Result(language: nil, light: nil, dark: nil)
        }
        return Result(
            language: language,
            light: highlight(text, language, .light),
            dark: highlight(text, language, .dark)
        )
    }

    private func finish(hash: String, generation: UUID, result: Result) {
        guard inFlight[hash] == generation else { return }
        inFlight.removeValue(forKey: hash)
        results[hash] = result
        revision += 1
    }

    private func persistOverrides() {
        if overrides.count > Self.maxOverrides {
            overrides = Dictionary(
                uniqueKeysWithValues: Array(overrides.prefix(Self.maxOverrides))
            )
        }
        defaults.set(overrides, forKey: Self.overridesKey)
    }
}
