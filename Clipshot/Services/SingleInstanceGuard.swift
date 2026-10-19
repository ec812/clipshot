import AppKit
import Darwin
import Foundation

/// Prevents multiple Clipshot processes from running at the same time.
///
/// Menu-bar (`LSUIElement`) apps often survive an Xcode "stop" or a relaunch.
/// A second process would create another status item, fail to own the Carbon
/// hotkeys, monitor the pasteboard twice, and contend on the same SQLite file.
final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()
    static let showOverlayNotification = Notification.Name("com.ernest.clipshot.show-overlay")

    private var lockFileDescriptor: Int32 = -1

    init() {}

    static func defaultLockURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Clipshot", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clipshot.lock")
    }

    /// Returns true when this process now owns the single-instance lock.
    /// Fails open only if the lock file cannot be created at all.
    func acquire(lockURL: URL? = nil) -> Bool {
        let url: URL
        if let lockURL {
            url = lockURL
        } else {
            do {
                url = try Self.defaultLockURL()
            } catch {
                NSLog("Clipshot: could not resolve single-instance lock path: \(error)")
                return true
            }
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            NSLog("Clipshot: could not open single-instance lock \(url.path)")
            return true
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        if lockFileDescriptor >= 0 {
            close(lockFileDescriptor)
        }
        lockFileDescriptor = descriptor

        ftruncate(descriptor, 0)
        let pidLine = "\(getpid())\n"
        _ = pidLine.withCString { pointer in
            Darwin.write(descriptor, pointer, strlen(pointer))
        }
        return true
    }

    func release() {
        if lockFileDescriptor >= 0 {
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    /// Best-effort activation of the already-running copy before the newcomer exits.
    func activateExistingInstance() {
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.ernest.clipshot")
            .filter { $0.processIdentifier != getpid() }

        if let existing = others.first {
            existing.activate(options: [.activateIgnoringOtherApps])
        }
        DistributedNotificationCenter.default().post(
            name: Self.showOverlayNotification,
            object: nil
        )
    }

    deinit {
        release()
    }
}
