import AppKit
import SwiftUI

/// Borderless, non-activating panel used for the bottom bar.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay NSPanel, its placement on the display under the pointer,
/// resizing, and keyboard interception while the timeline is visible.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    weak var appState: AppState?
    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var globalClickMonitor: Any?
    private(set) var isVisible = false

    static let edgeInset: CGFloat = 12
    static let minimumHeight: CGFloat = 150
    static let maximumHeight: CGFloat = 560
    static let compactThreshold: CGFloat = CardChromeStyle.fullOverlayMinimum

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    var isCompact: Bool {
        guard let appState else { return false }
        return appState.settings.alwaysCompact || currentHeight < Self.compactThreshold
    }

    private var currentHeight: CGFloat {
        guard let appState else { return 460 }
        return CGFloat(appState.settings.overlayHeight)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let appState else { return }
        if panel == nil {
            panel = makePanel(appState: appState)
        }
        guard let panel else { return }

        let screen = screenWithPointer()
        position(panel, on: screen)
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        installMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        removeMonitors()
    }

    /// Live resize while dragging. Deliberately does not touch settings: a
    /// UserDefaults write + whole-app publish on every drag event causes
    /// visible flicker (and needless activation-policy churn).
    func resize(to height: CGFloat) {
        setHeight(height, persist: false)
    }

    /// Persist the final height once the drag ends.
    func commitResize(to height: CGFloat) {
        setHeight(height, persist: true)
    }

    private func setHeight(_ height: CGFloat, persist: Bool) {
        guard let appState, let panel else { return }
        let clamped = min(max(height, Self.minimumHeight), Self.maximumHeight)
        if persist {
            appState.settings.overlayHeight = Double(clamped)
        }

        let screen = panel.screen ?? screenWithPointer()
        let frame = frame(for: screen, height: clamped)
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Panel

    private func makePanel(appState: AppState) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: frame(for: screenWithPointer(), height: currentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let hostingView = NSHostingView(rootView: TimelineView(appState: appState))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        return panel
    }

    private func frame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let width = max(640, visible.width - Self.edgeInset * 2)
        return NSRect(
            x: visible.minX + (visible.width - width) / 2,
            y: visible.minY + Self.edgeInset,
            width: width,
            height: height
        )
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrame(frame(for: screen, height: currentHeight), display: true)
    }

    private func screenWithPointer() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Event monitors

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isVisible, let appState = self.appState else { return event }
                if event.window === self.panel {
                    return appState.handleOverlayKey(event) ? nil : event
                }
                return event
            }
        }
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self, self.isVisible else { return event }
                if self.shouldDismiss(for: event) {
                    self.hide()
                }
                return event
            }
        }
        if globalClickMonitor == nil {
            // Clicks in other apps do not reach the local monitor.
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
        }
    }

    private func shouldDismiss(for event: NSEvent) -> Bool {
        guard let panel else { return false }
        if event.window === panel { return false }
        if let sheet = panel.attachedSheet, event.window === sheet { return false }
        if event.window?.sheetParent === panel { return false }
        if event.window?.parent === panel { return false }
        return true
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Intentionally empty: the click monitors decide when to dismiss, so that
        // sheets attached to the panel do not cause it to disappear.
    }
}
