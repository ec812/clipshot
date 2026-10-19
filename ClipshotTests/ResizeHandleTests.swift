import XCTest
@testable import Clipshot

final class ResizeHandleTests: XCTestCase {
    func testHeightFollowsGlobalPointerDelta() {
        XCTAssertEqual(
            ResizeHandle.height(startHeight: 300, startMouseY: 500, currentMouseY: 560),
            360
        )
        XCTAssertEqual(
            ResizeHandle.height(startHeight: 300, startMouseY: 500, currentMouseY: 440),
            240
        )
    }

    func testHeightIsQuantizedToWholePoints() {
        XCTAssertEqual(
            ResizeHandle.height(startHeight: 300, startMouseY: 500, currentMouseY: 500.4),
            300
        )
        XCTAssertEqual(
            ResizeHandle.height(startHeight: 300, startMouseY: 500, currentMouseY: 500.6),
            301
        )
    }
}
