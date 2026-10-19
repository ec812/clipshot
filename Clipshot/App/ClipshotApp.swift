import SwiftUI

@main
struct ClipshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let state = AppState(startMonitoring: !isTesting)
        _appState = StateObject(wrappedValue: state)
        AppDelegate.sharedState = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appState)
        } label: {
            Image(systemName: appState.isPaused ? "pause.circle" : "doc.on.clipboard")
                .accessibilityLabel("Clipshot")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.sharedState?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedState?.monitor.stop()
        Self.sharedState?.hotkeyManager.unregisterAll()
    }
}
