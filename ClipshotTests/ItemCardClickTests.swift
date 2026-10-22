import AppKit
import SwiftUI
import XCTest
@testable import Clipshot

@MainActor
final class ItemCardClickTests: XCTestCase {
    private final class Actions {
        var copy = 0
        var paste = 0
        var select = 0
    }

    private func makeCard(_ actions: Actions) -> ItemCard {
        let item = ClipboardItem(kind: .text, text: "hello world", hash: "test-hash")
        return ItemCard(
            item: item,
            isSelected: false,
            compact: false,
            appIcons: AppIconProvider(),
            clipImages: ClipImageStore(),
            codeHighlight: CodeHighlightStore(),
            linkPreviews: LinkPreviewStore(),
            fetchLinkPreviews: false,
            isPaused: false,
            onSelect: { actions.select += 1 },
            onPaste: { actions.paste += 1 },
            onCopy: { actions.copy += 1 },
            onPlainPaste: {},
            onShorten: {},
            onQR: {},
            onQROriginal: {},
            onPin: {},
            onExtractText: {},
            onAddToPinboard: { _ in },
            onRemoveFromPinboard: {},
            onDelete: {},
            onEdit: {},
            onRename: {},
            onAddToStack: {},
            pinboards: []
        )
    }

    private func makePanel(_ actions: Actions) -> NSPanel {
        let size = NSSize(width: 360, height: 460)
        let hosting = NSHostingView(rootView: makeCard(actions))
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.orderFrontRegardless()
        panel.makeKey()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return panel
    }

    /// The copy button is the first footer control: 9pt padding, 30pt button.
    private func copyButtonCenter(in panel: NSPanel) -> NSPoint {
        let height = panel.frame.height
        let footerHeight = CardChromeStyle.footerHeight(compact: false)
        let buttonSize = CardChromeStyle.footerButtonSize(compact: false)
        let x = CardChromeStyle.footerHorizontalPadding + buttonSize / 2
        let yFromTop = height - footerHeight + buttonSize / 2
        return NSPoint(x: x, y: height - yFromTop)
    }

    private func click(_ panel: NSPanel, at point: NSPoint, clickCount: Int) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events: [(NSEvent.EventType, Float)] = [(.leftMouseDown, 1), (.leftMouseUp, 0)]
        for (type, pressure) in events {
            let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: clickCount,
                pressure: pressure
            )!
            NSApp.sendEvent(event)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func warmUp(_ panel: NSPanel) {
        let point = NSPoint(x: panel.frame.width / 2, y: panel.frame.height * 0.55)
        click(panel, at: point, clickCount: 1)
    }

    func testSingleClickOnCopyButtonCopies() {
        let actions = Actions()
        let panel = makePanel(actions)
        defer { panel.close() }
        warmUp(panel)

        click(panel, at: copyButtonCenter(in: panel), clickCount: 1)

        XCTAssertEqual(actions.copy, 1, "Single click must run the copy action")
        XCTAssertEqual(actions.paste, 0, "Single click must not paste")
    }

    func testDoubleClickOnCopyButtonDoesNotPaste() {
        let actions = Actions()
        let panel = makePanel(actions)
        defer { panel.close() }
        warmUp(panel)

        let point = copyButtonCenter(in: panel)
        click(panel, at: point, clickCount: 1)
        click(panel, at: point, clickCount: 2)

        XCTAssertGreaterThan(actions.copy, 0, "The copy button must run its action")
        XCTAssertEqual(actions.paste, 0, "Double-clicking copy must not trigger the card's paste gesture")
    }
}
