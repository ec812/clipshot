import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(appState: appState) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 540)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Clipshot"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    let onFinish: () -> Void

    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipshot")
                        .font(.system(size: 24, weight: .bold))
                    Text("Clipboard history meets link shortening.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                feature("doc.on.clipboard", "Every copy is saved — text, links, images, files and colors.")
                feature("magnifyingglass", "⌘⇧V opens the timeline; type to search, ↩ to paste.")
                feature("link.badge.plus", "Shorten any link with ⌥⇧S; rules can do it automatically.")
                feature("qrcode", "⌥⇧Q renders a QR code for the selected item.")
                feature("lock.shield", "Local-first SQLite. No cloud sync, no tracking.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility permission")
                    .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 8) {
                    Image(systemName: appState.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.accessibilityTrusted ? .green : .orange)
                    Text(appState.accessibilityTrusted
                         ? "Granted — Clipshot can paste directly."
                         : "Needed to paste into other apps. Without it, Clipshot copies instead.")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !appState.accessibilityTrusted {
                        Button("Grant…") {
                            appState.requestAccessibility()
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bitly access token (optional)")
                    .font(.system(size: 12, weight: .semibold))
                SecureField("Paste your Bitly access token", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Link("Create a Bitly token at dev.bitly.com", destination: URL(string: "https://dev.bitly.com/")!)
                        .font(.system(size: 10))
                    Spacer()
                    Button("Save") {
                        appState.saveAPIKey(apiKey, for: appState.settings.activeBackendID)
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Without a token, the clipboard manager still works.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hotkeys")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(appState.settings.hotkey(for: .toggleOverlay).displayString) timeline · \(appState.settings.hotkey(for: .shorten).displayString) shorten · \(appState.settings.hotkey(for: .showQR).displayString) QR")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Get Started") {
                    appState.settings.hasCompletedOnboarding = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 540)
        .onAppear {
            appState.refreshAccessibility()
            apiKey = appState.apiKey(for: appState.settings.activeBackendID) ?? ""
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
