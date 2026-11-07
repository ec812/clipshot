import AppKit
import SwiftUI

/// AppKit dragging session with an explicit file pasteboard. SwiftUI `onDrag`
/// often fails to put `public.file-url` / filenames on the drag pasteboard for
/// Chromium file inputs; this path matches `PasteEngine.writeFileURL`.
struct ImageCardDragSource: NSViewRepresentable {
    let isEnabled: Bool
    let dragTemp: DragTempStore
    let item: ClipboardItem
    let previewImage: NSImage?

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.update(
            isEnabled: isEnabled,
            dragTemp: dragTemp,
            item: item,
            previewImage: previewImage
        )
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.update(
            isEnabled: isEnabled,
            dragTemp: dragTemp,
            item: item,
            previewImage: previewImage
        )
    }

    final class DragSourceView: NSView, NSDraggingSource {
        private var isEnabled = false
        private var dragTemp: DragTempStore?
        private var item: ClipboardItem?
        private var previewImage: NSImage?
        private var mouseDownLocation: NSPoint?
        private var beganDrag = false

        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            isEnabled ? self : nil
        }

        func update(
            isEnabled: Bool,
            dragTemp: DragTempStore,
            item: ClipboardItem,
            previewImage: NSImage?
        ) {
            self.isEnabled = isEnabled
            self.dragTemp = dragTemp
            self.item = item
            self.previewImage = previewImage
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
            beganDrag = false
            superview?.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, !beganDrag, let dragTemp, let item, let start = mouseDownLocation else { return }
            let delta = hypot(
                event.locationInWindow.x - start.x,
                event.locationInWindow.y - start.y
            )
            guard delta > 3 else { return }
            guard let fileURL = dragTemp.prepareDragFile(for: item) else { return }

            beganDrag = true
            let draggingItem = NSDraggingItem(
                pasteboardWriter: DragPasteboardProbe.explicitPasteboardItem(fileURL: fileURL)
            )
            let image = previewImage ?? NSImage(contentsOf: fileURL)
            if let image {
                draggingItem.setDraggingFrame(bounds, contents: image)
            } else {
                draggingItem.setDraggingFrame(bounds, contents: nil)
            }

            _ = beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if !beganDrag {
                superview?.mouseUp(with: event)
            }
            mouseDownLocation = nil
            beganDrag = false
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            [.copy]
        }
    }
}
