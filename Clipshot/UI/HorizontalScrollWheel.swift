import AppKit
import QuartzCore
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
///
/// Precise, high-rate input (MagSpeed / trackpad) is applied immediately.
/// Discrete thumb/tilt notches get an inertial coast so they feel closer to the
/// free-spinning vertical wheel instead of jumping one step at a time.
final class HorizontalScrollWheelMonitor: @unchecked Sendable {
    static let shared = HorizontalScrollWheelMonitor()

    /// Converts a discrete notch distance into an initial coast velocity (pt/s)
    /// so the notch is mostly covered over ~100ms before friction takes over.
    private static let notchCoastSeconds: CGFloat = 0.1
    private static let frictionPerFrame60: CGFloat = 0.88
    private static let stopSpeed: CGFloat = 12
    private static let maxFrameDelta: CFTimeInterval = 1.0 / 30.0

    private let scrollViews = NSHashTable<NSScrollView>.weakObjects()
    private var monitor: Any?
    private weak var activeScrollView: NSScrollView?

    private var velocity: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var inertiaTimer: Timer?

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
            if isEnd {
                activeScrollView = nil
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                    stopInertia()
                }
            }
            return event
        }

        activeScrollView = scrollView

        // Precise streams (MagSpeed, trackpad, momentum phases) already arrive as
        // many small steps — apply directly. Discrete thumb/tilt notches need a
        // synthesized coast or they feel like hard jumps.
        let isMomentum = event.momentumPhase != []
        if event.hasPreciseScrollingDeltas || isMomentum {
            stopInertia()
            HorizontalScrollWheel.scroll(scrollView, by: delta)
        } else {
            velocity += delta / Self.notchCoastSeconds
            startInertia(on: scrollView)
        }

        if isEnd { activeScrollView = nil }
        return nil
    }

    private func startInertia(on scrollView: NSScrollView) {
        activeScrollView = scrollView
        lastTick = CACurrentMediaTime()
        guard inertiaTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.inertiaTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        inertiaTimer = timer
    }

    private func inertiaTick() {
        guard let scrollView = activeScrollView ?? scrollViews.allObjects.first else {
            stopInertia()
            return
        }

        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, Self.maxFrameDelta)
        lastTick = now
        guard dt > 0 else { return }

        let step = velocity * CGFloat(dt)
        if abs(step) >= 0.05 {
            if !HorizontalScrollWheel.scroll(scrollView, by: step) {
                // Edge reached — kill residual speed.
                stopInertia()
                return
            }
        }

        velocity *= pow(Self.frictionPerFrame60, CGFloat(dt * 60))
        if abs(velocity) < Self.stopSpeed {
            stopInertia()
        }
    }

    private func stopInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        velocity = 0
    }

    private func targetScrollView(for event: NSEvent) -> NSScrollView? {
        if event.momentumPhase != [], let activeScrollView, activeScrollView.window === event.window {
            return activeScrollView
        }
        // Keep coasting with the same view while discrete notches keep arriving.
        if inertiaTimer != nil, let activeScrollView, activeScrollView.window === event.window {
            let locationInScrollView = activeScrollView.convert(event.locationInWindow, from: nil)
            if activeScrollView.bounds.contains(locationInScrollView) {
                return activeScrollView
            }
        }
        guard let window = event.window else { return nil }
        let locationInWindow = event.locationInWindow
        for scrollView in scrollViews.allObjects where scrollView.window === window {
            let locationInScrollView = scrollView.convert(locationInWindow, from: nil)
            if scrollView.bounds.contains(locationInScrollView) {
                return scrollView
            }
        }
        return nil
    }
}

enum HorizontalScrollWheel {
    /// Points advanced per line-based (non-precise) wheel notch.
    /// Larger than AppKit's default 10 so a thumb-wheel ratchet covers a
    /// comfortable card-width slice per click before inertia takes over.
    static let lineScrollPoints: CGFloat = 40

    /// The horizontal distance to scroll for a wheel event.
    ///
    /// Vertical-dominant events (an ordinary mouse wheel) are translated onto the
    /// horizontal axis. Horizontal-dominant events (a thumb/tilt wheel or trackpad
    /// two-finger horizontal swipe) scroll on their own axis, because leaving them
    /// to AppKit does not reliably scroll a SwiftUI `ScrollView(.horizontal)`.
    ///
    /// When both axes report movement, horizontal wins on a tie so Logitech-style
    /// thumb wheels with axis bleed still map correctly. If precise/scrolling
    /// deltas are empty, falls back to legacy line `deltaX`/`deltaY`.
    static func horizontalDelta(for event: NSEvent) -> CGFloat? {
        guard event.type == .scrollWheel else { return nil }
        return horizontalDelta(
            scrollingDeltaX: event.scrollingDeltaX,
            scrollingDeltaY: event.scrollingDeltaY,
            deltaX: event.deltaX,
            deltaY: event.deltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
    }

    /// Pure mapping used by `horizontalDelta(for:)` so HID edge cases are unit-testable.
    static func horizontalDelta(
        scrollingDeltaX: CGFloat,
        scrollingDeltaY: CGFloat,
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> CGFloat? {
        var horizontal = scrollingDeltaX
        var vertical = scrollingDeltaY
        var scale: CGFloat = hasPreciseScrollingDeltas ? 1 : lineScrollPoints

        if abs(horizontal) == 0, abs(vertical) == 0 {
            horizontal = deltaX
            vertical = deltaY
            scale = lineScrollPoints
        }

        guard abs(horizontal) > 0 || abs(vertical) > 0 else { return nil }

        // Prefer horizontal on ties — thumb wheels occasionally report equal bleed.
        if abs(horizontal) >= abs(vertical), abs(horizontal) > 0 {
            return horizontal * scale
        }
        return vertical * scale
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
