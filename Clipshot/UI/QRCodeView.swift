import AppKit
import SwiftUI

/// Floating window for QR codes with copy/export actions.
@MainActor
final class QRWindowController {
    private var window: NSWindow?

    func show(value: String, title: String) {
        guard let image = QRGenerator.image(for: value, scale: 14) else {
            NSSound.beep()
            return
        }

        let view = QRCodeView(value: value, title: title, image: image)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 470)

        let window = window ?? NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "QR Code"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct QRCodeView: View {
    let value: String
    let title: String
    let image: NSImage

    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 260)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy image") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if let tiff = image.tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                    }
                    copied = true
                }
                Button("Copy link") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(value, forType: .string)
                }
                Button("Save…") {
                    savePNG()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 460)
    }

    private func savePNG() {
        guard let data = QRGenerator.pngData(for: value, scale: 14) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "clipshot-qr.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
}
