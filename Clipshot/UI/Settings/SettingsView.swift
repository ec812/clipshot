import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettingsView(appState: appState)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            HotkeysSettingsView(appState: appState)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            IntegrationsSettingsView(appState: appState)
                .tabItem { Label("Integrations", systemImage: "link") }
        }
        .frame(width: 620, height: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            appState.reload()
            appState.refreshAccessibility()
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }

    private var competingAppNames: [String] {
        let identifiers: Set<String> = [
            "com.wiheads.paste",
            "com.pasteapp.mac",
            "com.shortmenu.shortmenu"
        ]
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard let bundleId = application.bundleIdentifier,
                  identifiers.contains(bundleId)
            else { return nil }
            return application.localizedName ?? bundleId
        }
    }

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep history", selection: $settings.retentionDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                Text("Pinned items and pinboards are never deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Items") {
                    Text("\(appState.items.count) loaded")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Window") {
                LabeledContent("Timeline height") {
                    HStack {
                        Slider(value: $settings.overlayHeight, in: 150...560, step: 10)
                            .frame(width: 220)
                        Text("\(Int(settings.overlayHeight)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
                Toggle("Always use compact cards", isOn: $settings.alwaysCompact)
                Toggle("Paste stack prefers short links", isOn: $settings.preferShortLinks)
            }

            Section("System") {
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)

                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            settings.launchAtLogin = newValue
                        } catch {
                            appState.lastError = error.localizedDescription
                            settings.launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                ))

                Button("Check Accessibility permission") {
                    appState.refreshAccessibility()
                }
                LabeledContent("Accessibility") {
                    Text(appState.accessibilityTrusted ? "Granted" : "Not granted")
                        .foregroundStyle(appState.accessibilityTrusted ? .green : .orange)
                }
                if !appState.accessibilityTrusted {
                    Button("Open System Settings…") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }

            Section("Previews") {
                Toggle("Fetch link previews (OG images)", isOn: $settings.fetchLinkPreviews)
                Button("Clear preview cache") {
                    appState.clearPreviewCache()
                }
                Text("Link previews are cached under ~/Library/Application Support/Clipshot/OGCache for 7 days, up to 200 MB. Fetches pause with clipboard capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Compatibility") {
                Toggle("Warn when a competing clipboard app is running", isOn: $settings.warnWhenPasteRunning)
                if settings.warnWhenPasteRunning {
                    if competingAppNames.isEmpty {
                        Text("No competing clipboard or shortener app detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Running alongside: \(competingAppNames.joined(separator: ", ")). Captures and hotkeys may overlap.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    @State private var newBundleId = ""

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }

    var body: some View {
        Form {
            Section("Capture") {
                if appState.isPaused {
                    LabeledContent("Status") {
                        Text("Paused")
                            .foregroundStyle(.orange)
                    }
                    Button("Resume capture") { appState.resumeCapture() }
                } else {
                    LabeledContent("Status") {
                        Text("Capturing")
                            .foregroundStyle(.green)
                    }
                    HStack {
                        Button("Pause 5 minutes") { appState.pause(for: 300) }
                        Button("Pause 15 minutes") { appState.pause(for: 900) }
                        Button("Pause 1 hour") { appState.pause(for: 3600) }
                    }
                }
            }

            Section("Privacy markers") {
                Toggle("Skip transient content", isOn: $settings.skipTransient)
                Text("Honors org.nspasteboard.TransientType and AutoGeneratedType markers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Skip concealed content", isOn: $settings.skipConcealed)
                Text("Honors concealment markers used by password managers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ignored apps") {
                ForEach(settings.ignoredBundleIds, id: \.self) { bundleId in
                    HStack {
                        Text(bundleId)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Button {
                            settings.ignoredBundleIds.removeAll { $0 == bundleId }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("com.example.app", text: $newBundleId)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let value = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !settings.ignoredBundleIds.contains(value) else { return }
                        settings.ignoredBundleIds.append(value)
                        newBundleId = ""
                    }
                }

                Text("Clipboard changes from these bundle identifiers are never captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys

struct HotkeysSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack {
                            HotkeyRecorderField(hotkey: settings.hotkey(for: action)) { hotkey in
                                appState.setHotkey(hotkey, for: action)
                            }
                            Button("Reset") {
                                appState.resetHotkey(for: action)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
                if let hotkeyError = appState.hotkeyError {
                    Text(hotkeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Click a shortcut, then press a new key combination. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In the timeline") {
                shortcutRow("← / →", "Move selection")
                shortcutRow("↩", "Paste selected item")
                shortcutRow("⇧↩", "Paste as plain text")
                shortcutRow("⌘1 – ⌘9", "Quick paste by position")
                shortcutRow("⌘N", "New text item")
                shortcutRow("⌘E / ⌘R", "Edit / rename")
                shortcutRow("⌘P", "Pin or unpin")
                shortcutRow("⌘K", "Shorten selected link")
                shortcutRow("␣", "Quick Look preview")
                shortcutRow("⌫", "Delete selected item")
            }

            Section {
                Button("Reset all shortcuts") {
                    settings.resetHotkeys()
                    appState.applyHotkeys()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        LabeledContent(label) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
        }
    }
}

struct HotkeyRecorderField: View {
    let hotkey: Hotkey
    let onChange: (Hotkey) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Press shortcut…" : hotkey.displayString)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let modifiers = Hotkey.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0,
                  Hotkey.keyName(for: UInt32(event.keyCode)) != "?"
            else {
                NSSound.beep()
                return nil
            }
            onChange(Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

// MARK: - Integrations

struct IntegrationsSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings

    @State private var apiKey = ""
    @State private var apiKeyLoaded = false
    @State private var ruleSheetMode: RuleSheetMode?

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }

    var body: some View {
        Form {
            Section("Shortening backend") {
                Picker("Provider", selection: $settings.activeBackendID) {
                    ForEach(appState.registry.descriptors, id: \.id) { descriptor in
                        Text(descriptor.displayName).tag(descriptor.id)
                    }
                }

                if let backend = appState.activeBackend {
                    LabeledContent("Capabilities") {
                        Text(capabilitySummary(backend.capabilities))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Status") {
                        Text(backend.isConfigured ? "Access token configured" : "No access token")
                            .foregroundStyle(backend.isConfigured ? .green : .orange)
                    }

                    SecureField("Bitly access token", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save token") {
                            appState.saveAPIKey(apiKey, for: settings.activeBackendID)
                        }
                        Button("Remove token") {
                            apiKey = ""
                            appState.saveAPIKey(nil, for: settings.activeBackendID)
                        }
                        Spacer()
                        Button(appState.isVerifyingBackend ? "Checking…" : "Test connection") {
                            Task { await appState.verifyBackend() }
                        }
                        .disabled(appState.isVerifyingBackend || !backend.isConfigured)
                    }

                    Link("Create a Bitly access token at dev.bitly.com", destination: URL(string: "https://dev.bitly.com/")!)
                        .font(.caption)

                    if let result = appState.credentialResult {
                        Text(credentialText(result))
                            .font(.caption)
                            .foregroundStyle(credentialColor(result))
                    }
                }
            }

            Section("Local MCP") {
                Toggle("Enable local MCP server", isOn: Binding(
                    get: { settings.mcpEnabled },
                    set: { appState.setMCPEnabled($0) }
                ))

                if settings.mcpEnabled {
                    if let url = settings.mcpURL {
                        LabeledContent("URL") {
                            HStack(spacing: 8) {
                                Text(url)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Button("Copy") { appState.copyToClipboard(url) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }

                    LabeledContent("Token") {
                        HStack(spacing: 8) {
                            Text(settings.mcpToken)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") { appState.copyToClipboard(settings.mcpToken) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }

                    if let error = appState.mcpError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if settings.mcpURL == nil {
                        Text("Starting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Clients connect over 127.0.0.1 only and must send \"Authorization: Bearer <token>\". The server can search history and read pinboards; its only writes are creating pinboards and adding items to them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Exposes clipboard history to local MCP clients (Claude, Hermes, Codex) over loopback HTTP with a bearer token. Off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Defaults") {
                TextField("Default domain", text: $settings.backendDefaultDomain)
                    .textFieldStyle(.roundedBorder)
                TextField("Bitly group GUID (optional)", text: $settings.backendGroupGUID)
                    .textFieldStyle(.roundedBorder)
                TextField("Default tags (comma separated)", text: $settings.backendDefaultTags)
                    .textFieldStyle(.roundedBorder)
                Text("Custom-slug links are created with POST /bitlinks (domain required). Auto-slug links use POST /shorten with bit.ly or your branded domain. Tags are applied with a follow-up PATCH on the auto path; slug changes are not supported by Bitly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-shorten rules") {
                if appState.rules.isEmpty {
                    Text("No rules yet. Add one to shorten links automatically when they are copied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(ruleSummary(rule))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(rule.isEnabled ? "Disable" : "Enable") {
                            var updated = rule
                            updated.isEnabled.toggle()
                            appState.saveRule(updated)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        Button("Edit") { ruleSheetMode = .edit(rule) }
                            .buttonStyle(.link)
                            .font(.caption)
                        Button("Delete", role: .destructive) { appState.deleteRule(rule) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Button("Add rule…") { ruleSheetMode = .new }
            }

            Section("Notes") {
                Text("Bitly API v4 supports POST /shorten, POST /bitlinks, PATCH /bitlinks/{bitlink} (long URL and tags), DELETE and click analytics. Clipshot caches every link it creates locally; use “Refresh Clicks” in Recent Links for all-time click counts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Open Bitly", destination: URL(string: "https://app.bitly.com/")!)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.reload()
            if !apiKeyLoaded {
                apiKey = appState.apiKey(for: settings.activeBackendID) ?? ""
                apiKeyLoaded = true
            }
        }
        .onChange(of: settings.activeBackendID) { _, _ in
            apiKey = appState.apiKey(for: settings.activeBackendID) ?? ""
            appState.credentialResult = nil
        }
        .sheet(item: $ruleSheetMode) { mode in
            RuleEditorSheet(appState: appState, mode: mode)
        }
    }

    private func capabilitySummary(_ capabilities: ShortenerCapabilities) -> String {
        var parts: [String] = []
        if capabilities.supportsCustomSlug { parts.append("custom slugs") }
        if capabilities.supportsCustomDomain { parts.append("domains") }
        if capabilities.supportsTags { parts.append("tags") }
        if capabilities.supportsDelete { parts.append("delete") }
        if capabilities.supportsClickStats { parts.append("click stats") }
        return parts.isEmpty ? "basic" : parts.joined(separator: " · ")
    }

    private func credentialText(_ result: ShortenerCredentialResult) -> String {
        switch result {
        case .valid: return "Bitly access token accepted."
        case .invalid: return "Bitly access token rejected."
        case .unavailable(let message): return "Could not verify: \(message)"
        }
    }

    private func credentialColor(_ result: ShortenerCredentialResult) -> Color {
        switch result {
        case .valid: return .green
        case .invalid: return .red
        case .unavailable: return .orange
        }
    }

    private func ruleSummary(_ rule: ShortenRule) -> String {
        var parts = [rule.urlPattern.isEmpty ? "*" : rule.urlPattern]
        if let source = rule.sourceAppPattern, !source.isEmpty { parts.append("in \(source)") }
        if let domain = rule.domain, !domain.isEmpty { parts.append("→ \(domain)") }
        if let template = rule.slugTemplate, !template.isEmpty { parts.append("slug: \(template)") }
        parts.append(rule.autoCopy ? "auto-copy" : "no copy")
        return parts.joined(separator: " · ")
    }
}

enum RuleSheetMode: Identifiable {
    case new
    case edit(ShortenRule)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let rule): return "edit-\(rule.id ?? -1)"
        }
    }
}

struct RuleEditorSheet: View {
    @ObservedObject var appState: AppState
    let mode: RuleSheetMode

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlPattern = "*"
    @State private var sourceAppPattern = ""
    @State private var domain = ""
    @State private var slugTemplate = ""
    @State private var autoCopy = true
    @State private var isEnabled = true
    @State private var priority = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-shorten rule")
                .font(.system(size: 16, weight: .semibold))

            Form {
                TextField("Name", text: $name)
                TextField("URL pattern (glob)", text: $urlPattern)
                TextField("Source app pattern (optional)", text: $sourceAppPattern)
                TextField("Domain (optional)", text: $domain)
                TextField("Slug template (optional)", text: $slugTemplate)
                Text("Tokens: {host} {path} {word} {date} {rand}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Copy short link after shortening", isOn: $autoCopy)
                Toggle("Enabled", isOn: $isEnabled)
                Stepper("Priority: \(priority)", value: $priority, in: 0...100)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440, height: 470)
        .onAppear(perform: load)
    }

    private func load() {
        guard case .edit(let rule) = mode else { return }
        name = rule.name
        urlPattern = rule.urlPattern
        sourceAppPattern = rule.sourceAppPattern ?? ""
        domain = rule.domain ?? ""
        slugTemplate = rule.slugTemplate ?? ""
        autoCopy = rule.autoCopy
        isEnabled = rule.isEnabled
        priority = rule.priority
    }

    private func save() {
        var rule: ShortenRule
        if case .edit(let existing) = mode {
            rule = existing
        } else {
            rule = ShortenRule(name: name)
        }
        rule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.urlPattern = urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.sourceAppPattern = sourceAppPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : sourceAppPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : domain.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.slugTemplate = slugTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : slugTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.autoCopy = autoCopy
        rule.isEnabled = isEnabled
        rule.priority = priority
        appState.saveRule(rule)
        dismiss()
    }
}
