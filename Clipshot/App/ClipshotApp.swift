import SwiftUI

@main
struct ClipshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isTesting {
            guard SingleInstanceGuard.shared.acquire() else {
                NSLog("Clipshot: another instance is already running; activating it and exiting (pid \(getpid()))")
                SingleInstanceGuard.shared.activateExistingInstance()
                exit(0)
            }
            NSLog("Clipshot: single-instance lock acquired (pid \(getpid()))")
        }
        let state = AppState(startMonitoring: !isTesting)
        _appState = StateObject(wrappedValue: state)
        AppDelegate.sharedState = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appState)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel("Clipshot")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState)
        }
    }

    private var menuBarSymbol: String {
        if appState.hotkeyError != nil { return "exclamationmark.triangle" }
        return appState.isPaused ? "pause.circle" : "doc.on.clipboard"
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
