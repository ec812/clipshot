import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let hotkeyError = appState.hotkeyError {
            Text("Shortcuts unavailable: \(hotkeyError)")
            Divider()
        }

        Button("Open Clipboard Timeline") {
            appState.overlayController.show()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Button("New Text Item…") {
            appState.overlayController.show()
            appState.beginNewSnippet()
        }

        Divider()

        Menu(appState.isPaused ? "Capture Paused" : "Pause Capture") {
            Button("Pause 5 minutes") { appState.pause(for: 300) }
            Button("Pause 15 minutes") { appState.pause(for: 900) }
            Button("Pause 1 hour") { appState.pause(for: 3600) }
            if appState.isPaused {
                Divider()
                Button("Resume Now") { appState.resumeCapture() }
            }
        }

        Menu("Recent Links") {
            if appState.recentShortLinks.isEmpty {
                Text("No links yet — shorten one from the timeline")
            } else {
                ForEach(Array(appState.recentShortLinks.prefix(12))) { link in
                    Menu(linkMenuTitle(link)) {
                        Button("Copy Short Link") {
                            appState.copyToClipboard(link.shortUrl)
                        }
                        Button("Open Short Link") {
                            if let url = URL(string: link.shortUrl) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Open Destination") {
                            if let url = URL(string: link.destinationUrl) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Divider()
                        if appState.activeBackend?.capabilities.supportsClickStats == true {
                            Button(
                                appState.refreshingClickLinkID == link.id
                                    ? "Refreshing Clicks…"
                                    : "Refresh Clicks"
                            ) {
                                Task { await appState.refreshClicks(for: link) }
                            }
                            .disabled(appState.refreshingClickLinkID != nil)
                        }
                        Button("Open Bitly Analytics") {
                            NSWorkspace.shared.open(URL(string: "https://app.bitly.com/")!)
                        }
                    }
                }
                Divider()
                Button("Open Bitly") {
                    NSWorkspace.shared.open(URL(string: "https://app.bitly.com/")!)
                }
            }
        }

        if appState.pasteStack.isActive {
            Menu("Paste Stack (\(appState.pasteStackCount))") {
                Button("Paste Next Item") { appState.pasteNextInStack() }
                Button("Clear Stack") { appState.clearPasteStack() }
            }
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Clipshot") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func linkMenuTitle(_ link: ShortLink) -> String {
        let clicks = link.clickCount.map { " · \($0) click\($0 == 1 ? "" : "s")" } ?? ""
        return "\(link.shortUrl)\(clicks)  →  \(hostLabel(link.destinationUrl))"
    }

    private func hostLabel(_ value: String) -> String {
        URL(string: value)?.host ?? value
    }
}
