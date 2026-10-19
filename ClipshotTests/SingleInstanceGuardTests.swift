import XCTest
@testable import Clipshot

final class SingleInstanceGuardTests: XCTestCase {
    func testSecondAcquireFailsUntilFirstReleases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("test.lock")

        let first = SingleInstanceGuard()
        XCTAssertTrue(first.acquire(lockURL: lockURL))

        let second = SingleInstanceGuard()
        XCTAssertFalse(second.acquire(lockURL: lockURL))

        let contents = try String(contentsOf: lockURL, encoding: .utf8)
        XCTAssertEqual(contents.trimmingCharacters(in: .whitespacesAndNewlines), "\(getpid())")

        first.release()
        XCTAssertTrue(second.acquire(lockURL: lockURL))
        second.release()
    }
}
