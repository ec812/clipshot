import AppKit
import XCTest
@testable import Clipshot

final class HorizontalScrollWheelTests: XCTestCase {
    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 100))
        scrollView.contentView.scroll(to: .zero)
        return scrollView
    }

    private func scrollEvent(deltaX: Int32, deltaY: Int32, precise: Bool = true) -> NSEvent {
        let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: precise ? .pixel : .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )!
        if precise {
            cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(deltaX))
        return NSEvent(cgEvent: cgEvent)!
    }

    func testVerticalEventMapsToHorizontalDelta() {
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 0, deltaY: 12)), 12)
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 0, deltaY: -12)), -12)
    }

    func testHorizontalDominantEventMapsToHorizontalDelta() {
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 10, deltaY: 2)), 10)
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: -10, deltaY: 0)), -10)
    }

    func testEqualAxisTiePrefersHorizontal() {
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 8, deltaY: 8)), 8)
        XCTAssertEqual(HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: -8, deltaY: 8)), -8)
    }

    func testLegacyDeltaXFallbackWhenScrollingDeltasEmpty() {
        // CGEvent always mirrors wheel ticks into scrollingDelta*, so exercise the
        // pure mapper with empty scrolling deltas and a legacy horizontal tick.
        XCTAssertEqual(
            HorizontalScrollWheel.horizontalDelta(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                deltaX: 2,
                deltaY: 0,
                hasPreciseScrollingDeltas: false
            ),
            80
        )
        XCTAssertEqual(
            HorizontalScrollWheel.horizontalDelta(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                deltaX: -3,
                deltaY: 1,
                hasPreciseScrollingDeltas: true
            ),
            -120
        )
    }

    func testLineBasedEventsUseLineHeight() {
        XCTAssertEqual(
            HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 0, deltaY: 3, precise: false)),
            120
        )
        XCTAssertEqual(
            HorizontalScrollWheel.horizontalDelta(for: scrollEvent(deltaX: 4, deltaY: 0, precise: false)),
            160
        )
    }

    func testSyntheticVerticalEventScrollsHorizontally() {
        let scrollView = makeScrollView()
        scrollView.contentView.scroll(to: NSPoint(x: 100, y: 0))

        let event = scrollEvent(deltaX: 0, deltaY: -30)
        guard let delta = HorizontalScrollWheel.horizontalDelta(for: event) else {
            return XCTFail("Vertical event should produce a horizontal delta")
        }
        XCTAssertTrue(HorizontalScrollWheel.scroll(scrollView, by: delta))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 70)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0)
    }

    func testSyntheticHorizontalEventScrollsHorizontally() {
        let scrollView = makeScrollView()
        scrollView.contentView.scroll(to: NSPoint(x: 100, y: 0))

        let event = scrollEvent(deltaX: -30, deltaY: 0)
        guard let delta = HorizontalScrollWheel.horizontalDelta(for: event) else {
            return XCTFail("Horizontal event should produce a horizontal delta")
        }
        XCTAssertTrue(HorizontalScrollWheel.scroll(scrollView, by: delta))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 70)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0)
    }

    func testScrollingClampsToScrollableRange() {
        let scrollView = makeScrollView()

        scrollView.contentView.scroll(to: NSPoint(x: 10, y: 0))
        XCTAssertTrue(HorizontalScrollWheel.scroll(scrollView, by: -50))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0)

        scrollView.contentView.scroll(to: NSPoint(x: 690, y: 0))
        XCTAssertTrue(HorizontalScrollWheel.scroll(scrollView, by: 50))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 700)
    }

    func testNoMovementAtEdgeReturnsFalse() {
        let scrollView = makeScrollView()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        XCTAssertFalse(HorizontalScrollWheel.scroll(scrollView, by: -40))
    }
}
