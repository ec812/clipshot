import AppKit
import SwiftUI

/// Discovers the `NSScrollView` backing a horizontal SwiftUI `ScrollView` and
/// registers it for vertical-wheel-to-horizontal scrolling.
///
/// Place this inside the scroll view's content, for example as a background.
struct HorizontalScrollWheelAdapter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AdapterView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AdapterView)?.attach()
    }

    private final class AdapterView: NSView {
        private var didScheduleRetry = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func layout() {
            super.layout()
            attach()
        }

        func attach() {
            guard window != nil else { return }
            if let scrollView = enclosingScrollView {
                HorizontalScrollWheelMonitor.shared.register(scrollView)
            } else if !didScheduleRetry {
                didScheduleRetry = true
                DispatchQueue.main.async { [weak self] in
                    self?.didScheduleRetry = false
                    self?.attach()
                }
            }
        }
    }
}

/// Translates vertical scroll-wheel deltas into horizontal scrolling for the
/// scroll views registered by `HorizontalScrollWheelAdapter`.
///
/// A single local monitor handles every registered view, but it only acts while
/// the pointer is over one of them; all other scrolling is left untouched.
final class HorizontalScrollWheelMonitor: @unchecked Sendable {
    static let shared = HorizontalScrollWheelMonitor()

    private let scrollViews = NSHashTable<NSScrollView>.weakObjects()
    private var monitor: Any?
    private weak var activeScrollView: NSScrollView?

    func register(_ scrollView: NSScrollView) {
        scrollViews.add(scrollView)
        installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let scrollView = targetScrollView(for: event) else { return event }

        let isEnd = event.phase == .ended || event.phase == .cancelled
            || event.momentumPhase == .ended || event.momentumPhase == .cancelled

        guard let delta = HorizontalScrollWheel.horizontalDelta(for: event) else {
            if isEnd { activeScrollView = nil }
            return event
        }

        activeScrollView = scrollView
        HorizontalScrollWheel.scroll(scrollView, by: delta)
        if isEnd { activeScrollView = nil }
        return nil
    }

    private func targetScrollView(for event: NSEvent) -> NSScrollView? {
        if event.momentumPhase != [], let activeScrollView, activeScrollView.window === event.window {
            return activeScrollView
        }
        guard let window = event.window,
              let hitView = window.contentView?.hitTest(event.locationInWindow) else {
            return nil
        }
        for scrollView in scrollViews.allObjects where hitView.isDescendant(of: scrollView) {
            return scrollView
        }
        return nil
    }
}

enum HorizontalScrollWheel {
    /// NSScrollView advances horizontal wheel scrolling by 10 points per line.
    static let lineScrollPoints: CGFloat = 10

    /// The horizontal distance to scroll for a vertical-dominant wheel event.
    /// Returns `nil` for horizontal-dominant events, which AppKit scrolls natively.
    static func horizontalDelta(for event: NSEvent) -> CGFloat? {
        guard event.type == .scrollWheel else { return nil }
        let horizontal = abs(event.scrollingDeltaX)
        let vertical = abs(event.scrollingDeltaY)
        guard vertical > horizontal, vertical > 0 else { return nil }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : lineScrollPoints
        return event.scrollingDeltaY * scale
    }

    /// Moves the scroll view horizontally, clamped to its scrollable range.
    @discardableResult
    static func scroll(_ scrollView: NSScrollView, by delta: CGFloat) -> Bool {
        let clipView = scrollView.contentView
        let current = clipView.bounds
        let documentWidth = scrollView.documentView?.frame.width ?? current.width
        let maxX = max(0, documentWidth - current.width)
        let targetX = min(max(0, current.origin.x + delta), maxX)
        guard targetX != current.origin.x else { return false }
        clipView.scroll(to: NSPoint(x: targetX, y: current.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }
}
