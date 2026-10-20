# Card Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the card header/bottom metadata with a Paste-style app band and a persistent icon footer, without changing the per-kind previews or card actions.

**Architecture:** Add a focused `CardChrome.swift` containing `CardChromeStyle` (pure values), `CardBand`, and `CardFooter`. `ItemCard` composes band + existing preview + footer. Raise the default overlay height and compact threshold so the chrome fits.

**Tech Stack:** Swift 5 language mode, SwiftUI, AppKit, XCTest, macOS 14 deployment target, hand-maintained `Clipshot.xcodeproj/project.pbxproj`.

**Branch:** `feature/card-restyle`, created from current `main`.

---

## File Structure

**Create**

- `Clipshot/UI/CardChrome.swift` — band, footer, and pure chrome style.
- `ClipshotTests/CardChromeStyleTests.swift` — pure style tests.

**Modify**

- `Clipshot/UI/ItemCard.swift` — compose the new chrome; remove old header/metadata/action row; full-bleed color body.
- `Clipshot/UI/OverlayController.swift` — compact threshold 450; fallback height 460.
- `Clipshot/Services/AppSettings.swift` — default overlay height 460.
- `Clipshot.xcodeproj/project.pbxproj` — add the two new Swift files to their targets.
- `TESTING.md` — card matrix, compact/default-height note, test count.
- `Docs/verify-card-restyle.png` — visual evidence.

**Unchanged**

- `URLPreviewView` inside `ItemCard.swift`.
- Card context menu behavior.
- Timeline/filter/search code.
- Card action callbacks in `TimelineView`/`AppState`.

---

## Task 1: Add the chrome style and its tests

**Files:**
- Create: `Clipshot/UI/CardChrome.swift`
- Create: `ClipshotTests/CardChromeStyleTests.swift`
- Modify: `Clipshot.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the feature branch**

Run:

```bash
cd /Users/ernest/projects/clipboard
git switch main
git switch -c feature/card-restyle
```

Expected: `Switched to a new branch 'feature/card-restyle'`.

- [ ] **Step 2: Write the failing `CardChromeStyleTests`**

Create `ClipshotTests/CardChromeStyleTests.swift`:

```swift
import AppKit
import XCTest
@testable import Clipshot

final class CardChromeStyleTests: XCTestCase {
    private let safariBlue = NSColor(
        srgbRed: 0.094,
        green: 0.555,
        blue: 0.885,
        alpha: 1
    )

    func testBandTintIsStrongerInDarkModeAndWhenSelected() throws {
        let dark = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: false,
                colorScheme: .dark
            )
        )
        let light = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: false,
                colorScheme: .light
            )
        )
        let selectedDark = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: true,
                colorScheme: .dark
            )
        )

        XCTAssertEqual(dark.opacity, 0.34, accuracy: 0.001)
        XCTAssertEqual(light.opacity, 0.20, accuracy: 0.001)
        XCTAssertEqual(selectedDark.opacity, 0.40, accuracy: 0.001)
        XCTAssertGreaterThan(dark.opacity, light.opacity)
        XCTAssertGreaterThan(selectedDark.opacity, dark.opacity)
        XCTAssertEqual(dark.red, 0.094, accuracy: 0.001)
        XCTAssertEqual(dark.green, 0.555, accuracy: 0.001)
        XCTAssertEqual(dark.blue, 0.885, accuracy: 0.001)
    }

    func testMissingAccentHasNoTint() {
        XCTAssertNil(
            CardChromeStyle.bandTint(
                for: nil,
                isSelected: false,
                colorScheme: .dark
            )
        )
        XCTAssertNil(
            CardChromeStyle.bandTint(
                for: nil,
                isSelected: true,
                colorScheme: .light
            )
        )
    }

    func testFullAndCompactChromeDimensions() {
        XCTAssertEqual(CardChromeStyle.bandHeight(compact: false), 58)
        XCTAssertEqual(CardChromeStyle.bandHeight(compact: true), 50)
        XCTAssertEqual(CardChromeStyle.iconSize(compact: false), 40)
        XCTAssertEqual(CardChromeStyle.iconSize(compact: true), 32)
        XCTAssertEqual(CardChromeStyle.footerHeight(compact: false), 36)
        XCTAssertEqual(CardChromeStyle.footerHeight(compact: true), 32)
        XCTAssertEqual(CardChromeStyle.footerButtonSize(compact: false), 30)
        XCTAssertEqual(CardChromeStyle.footerButtonSize(compact: true), 26)
        XCTAssertEqual(CardChromeStyle.cornerRadius, 14)
        XCTAssertEqual(CardChromeStyle.fullOverlayMinimum, 450)
    }

    func testCompactThresholdBoundary() {
        XCTAssertTrue(CardChromeStyle.isCompact(overlayHeight: 449, alwaysCompact: false))
        XCTAssertFalse(CardChromeStyle.isCompact(overlayHeight: 450, alwaysCompact: false))
        XCTAssertFalse(CardChromeStyle.isCompact(overlayHeight: 560, alwaysCompact: false))
        XCTAssertTrue(CardChromeStyle.isCompact(overlayHeight: 560, alwaysCompact: true))
    }
}
```

- [ ] **Step 3: Wire the new files into the project**

Edit `Clipshot.xcodeproj/project.pbxproj` exactly.

Add to the `PBXBuildFile` section after the `ItemCard.swift in Sources` build file:

```text
		7A1B2C3D4E5F60718293A4B6 /* CardChrome.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7A1B2C3D4E5F60718293A4B5 /* CardChrome.swift */; };
		7A1B2C3D4E5F60718293A4B8 /* CardChromeStyleTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7A1B2C3D4E5F60718293A4B7 /* CardChromeStyleTests.swift */; };
```

Add to `PBXFileReference` after the `ItemCard.swift` reference:

```text
		7A1B2C3D4E5F60718293A4B5 /* CardChrome.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Clipshot/UI/CardChrome.swift; sourceTree = "<group>"; };
```

Add to `PBXFileReference` after the `CardAccentStyleTests.swift` reference:

```text
		7A1B2C3D4E5F60718293A4B7 /* CardChromeStyleTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ClipshotTests/CardChromeStyleTests.swift; sourceTree = "<group>"; };
```

Add to the `Clipshot` group's children after `ItemCard.swift`:

```text
				7A1B2C3D4E5F60718293A4B5 /* CardChrome.swift */,
```

Add to the `ClipshotTests` group's children after `CardAccentStyleTests.swift`:

```text
				7A1B2C3D4E5F60718293A4B7 /* CardChromeStyleTests.swift */,
```

Add to the app `PBXSourcesBuildPhase` after `ItemCard.swift in Sources`:

```text
				7A1B2C3D4E5F60718293A4B6 /* CardChrome.swift in Sources */,
```

Add to the test `PBXSourcesBuildPhase` after `CardAccentStyleTests.swift in Sources`:

```text
				7A1B2C3D4E5F60718293A4B8 /* CardChromeStyleTests.swift in Sources */,
```

Verify the project parses:

```bash
plutil -lint Clipshot.xcodeproj/project.pbxproj
```

Expected: `Clipshot.xcodeproj/project.pbxproj: OK`.

- [ ] **Step 4: Run the test to see it fail**

Run:

```bash
xcodebuild -scheme Clipshot test \
  -only-testing:ClipshotTests/CardChromeStyleTests
```

Expected: FAIL to compile with `cannot find 'CardChromeStyle' in scope`.

- [ ] **Step 5: Add `CardChromeStyle`**

Create `Clipshot/UI/CardChrome.swift` with only the style section for now:

```swift
import AppKit
import SwiftUI

enum CardChromeStyle {
    static let cornerRadius: CGFloat = 14
    static let fullOverlayMinimum: CGFloat = 450

    static let bandHorizontalPadding: CGFloat = 11
    static let bodyHorizontalPadding: CGFloat = 12
    static let bodyVerticalPadding: CGFloat = 10
    static let footerHorizontalPadding: CGFloat = 9

    static func isCompact(overlayHeight: CGFloat, alwaysCompact: Bool) -> Bool {
        alwaysCompact || overlayHeight < fullOverlayMinimum
    }

    static func bandHeight(compact: Bool) -> CGFloat {
        compact ? 50 : 58
    }

    static func iconSize(compact: Bool) -> CGFloat {
        compact ? 32 : 40
    }

    static func iconCornerRadius(compact: Bool) -> CGFloat {
        compact ? 8 : 10
    }

    static func footerHeight(compact: Bool) -> CGFloat {
        compact ? 32 : 36
    }

    static func footerButtonSize(compact: Bool) -> CGFloat {
        compact ? 26 : 30
    }

    static func footerGlyphSize(compact: Bool) -> CGFloat {
        compact ? 13 : 15
    }

    static func bandTint(
        for accent: NSColor?,
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> AccentTint? {
        guard let rgb = accent?.usingColorSpace(.sRGB) else { return nil }
        let base = colorScheme == .dark ? 0.34 : 0.20
        let opacity = min(0.95, base + (isSelected ? 0.06 : 0))
        return AccentTint(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            opacity: opacity
        )
    }

    static func bandGradient(for tint: AccentTint?) -> LinearGradient {
        if let tint {
            let base = Color(
                red: tint.red,
                green: tint.green,
                blue: tint.blue
            )
            return LinearGradient(
                colors: [
                    base.opacity(tint.opacity),
                    base.opacity(tint.opacity * 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.primary.opacity(0.07),
                Color.primary.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

- [ ] **Step 6: Run the style tests**

Run:

```bash
xcodebuild -scheme Clipshot test \
  -only-testing:ClipshotTests/CardChromeStyleTests
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Clipshot/UI/CardChrome.swift \
  ClipshotTests/CardChromeStyleTests.swift \
  Clipshot.xcodeproj/project.pbxproj
git commit -m "Add card chrome style and tests"
```

---

## Task 2: Add the app band

**Files:**
- Modify: `Clipshot/UI/CardChrome.swift`

- [ ] **Step 1: Append `CardBand`**

Append to `Clipshot/UI/CardChrome.swift` after `CardChromeStyle`:

```swift
struct CardBand: View {
    let icon: NSImage?
    let sourceApp: String
    let kind: ClipboardItemKind
    let relativeTime: String
    let accent: NSColor?
    let isSelected: Bool
    let isPinned: Bool
    let hasShortLink: Bool
    let isSnippet: Bool
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var tint: AccentTint? {
        CardChromeStyle.bandTint(
            for: accent,
            isSelected: isSelected,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceApp)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)

                Text("\(kind.displayName.uppercased()) · \(relativeTime)")
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            statusGlyphs
        }
        .padding(.horizontal, CardChromeStyle.bandHorizontalPadding)
        .frame(height: CardChromeStyle.bandHeight(compact: compact))
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                CardChromeStyle.bandGradient(for: tint)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var appIcon: some View {
        let size = CardChromeStyle.iconSize(compact: compact)

        return Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: compact ? 15 : 18))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CardChromeStyle.iconCornerRadius(compact: compact),
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 2, y: 1)
    }

    @ViewBuilder
    private var statusGlyphs: some View {
        HStack(spacing: 5) {
            if isSnippet {
                Image(systemName: "text.badge.plus")
            }
            if hasShortLink {
                Image(systemName: "link")
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: compact ? 9 : 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -scheme Clipshot build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Clipshot/UI/CardChrome.swift
git commit -m "Add app band card chrome"
```

---

## Task 3: Add the persistent icon footer

**Files:**
- Modify: `Clipshot/UI/CardChrome.swift`

- [ ] **Step 1: Append `CardFooter`**

Append to `Clipshot/UI/CardChrome.swift` after `CardBand`:

```swift
struct CardFooter: View {
    let kind: ClipboardItemKind
    let isPinned: Bool
    let compact: Bool

    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onPlainPaste: () -> Void
    let onShorten: () -> Void
    let onQR: () -> Void
    let onAddToStack: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            iconButton("doc.on.doc", help: "Copy item", action: onCopy)
            iconButton(
                "doc.on.clipboard",
                help: "Paste item",
                primary: true,
                action: onPaste
            )
            iconButton(
                isPinned ? "pin.fill" : "pin",
                help: isPinned ? "Unpin item" : "Pin item",
                action: onPin
            )
            overflowMenu
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CardChromeStyle.footerHorizontalPadding)
        .frame(height: CardChromeStyle.footerHeight(compact: compact))
        .background(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var buttonSize: CGFloat {
        CardChromeStyle.footerButtonSize(compact: compact)
    }

    private var overflowMenu: some View {
        Menu {
            if kind == .text || kind == .url || kind == .rtf {
                Button {
                    onPlainPaste()
                } label: {
                    Label("Paste as Plain Text", systemImage: "textformat")
                }
            }
            if kind == .url {
                Button {
                    onShorten()
                } label: {
                    Label("Shorten…", systemImage: "link.badge.plus")
                }
            }
            if kind != .color {
                Button {
                    onQR()
                } label: {
                    Label("Show QR Code", systemImage: "qrcode")
                }
            }
            Button {
                onAddToStack()
            } label: {
                Label("Add to Paste Stack", systemImage: "rectangle.stack.badge.plus")
            }
            if kind == .text || kind == .url {
                Button {
                    onEdit()
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
            }
            Button {
                onRename()
            } label: {
                Label("Rename…", systemImage: "character.cursor.ibeam")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(
                    .system(
                        size: CardChromeStyle.footerGlyphSize(compact: compact),
                        weight: .medium
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.07))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private func iconButton(
        _ systemImage: String,
        help: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        FooterIconButton(
            systemImage: systemImage,
            help: help,
            primary: primary,
            size: buttonSize,
            glyphSize: CardChromeStyle.footerGlyphSize(compact: compact),
            action: action
        )
    }
}

private struct FooterIconButton: View {
    let systemImage: String
    let help: String
    let primary: Bool
    let size: CGFloat
    let glyphSize: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var backgroundColor: Color {
        if primary {
            return Color.accentColor.opacity(isHovered ? 0.30 : 0.22)
        }
        return Color.primary.opacity(isHovered ? 0.12 : 0.07)
    }

    private var borderColor: Color {
        primary
            ? Color.accentColor.opacity(isHovered ? 0.65 : 0.45)
            : Color.clear
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -scheme Clipshot build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Clipshot/UI/CardChrome.swift
git commit -m "Add persistent card action footer"
```

---

## Task 4: Rebuild `ItemCard` around the chrome

**Files:**
- Modify: `Clipshot/UI/ItemCard.swift`

- [ ] **Step 1: Replace the card body and chrome properties**

In `Clipshot/UI/ItemCard.swift`, replace the existing `body`, `cardBackground`, `cardBorder`, `backgroundColor`, and `accentNSColor` blocks with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            CardBand(
                icon: appIcons.icon(for: item.bundleId),
                sourceApp: item.sourceApp ?? "Unknown",
                kind: item.kind,
                relativeTime: relativeTime,
                accent: appIcons.accent(for: item.bundleId),
                isSelected: isSelected,
                isPinned: item.isPinned,
                hasShortLink: item.hasShortLink,
                isSnippet: item.isSnippet,
                compact: compact
            )

            preview
                .padding(
                    .horizontal,
                    item.kind == .color ? 0 : CardChromeStyle.bodyHorizontalPadding
                )
                .padding(
                    .vertical,
                    item.kind == .color ? 0 : CardChromeStyle.bodyVerticalPadding
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            CardFooter(
                kind: item.kind,
                isPinned: item.isPinned,
                compact: compact,
                onCopy: onCopy,
                onPaste: onPaste,
                onPin: onPin,
                onPlainPaste: onPlainPaste,
                onShorten: onShorten,
                onQR: onQR,
                onAddToStack: onAddToStack,
                onEdit: onEdit,
                onRename: onRename
            )
        }
        .frame(width: max(Self.minimumWidth, compact ? 138 : 204))
        .frame(maxHeight: .infinity)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CardChromeStyle.cornerRadius,
                style: .continuous
            )
        )
        .overlay(cardBorder)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPaste() }
        .onTapGesture { onSelect() }
        .contextMenu { contextMenu }
        .help(item.displayText)
        .onAppear {
            appIcons.ensureLoaded(bundleId: item.bundleId)
            clipImages.ensureLoaded(path: item.dataPath)
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? Color.primary.opacity(0.09)
                    : Color.primary.opacity(0.05)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(
            cornerRadius: CardChromeStyle.cornerRadius,
            style: .continuous
        )
        .stroke(
            borderColor,
            lineWidth: CardAccentStyle.borderWidth(isSelected: isSelected)
        )
    }

    private var borderColor: Color {
        if let tint = CardAccentStyle.borderTint(
            for: accentNSColor,
            isSelected: isSelected
        ) {
            return tint.color
        }
        if isSelected { return Color.accentColor.opacity(0.9) }
        return Color.primary.opacity(0.12)
    }

    private var accentNSColor: NSColor? {
        appIcons.accent(for: item.bundleId)
    }
```

- [ ] **Step 2: Make the color preview full-bleed**

Replace the color case's `RoundedRectangle(cornerRadius: 8, style: .continuous)` fill, frame, clip, and stroke with a plain `Rectangle`:

```swift
        case .color:
            if let text = item.text, let parsed = ClipboardColorParser.parse(text) {
                let background = colorScheme == .dark
                    ? ColorCardStyle.darkBackground
                    : ColorCardStyle.lightBackground
                let foreground = ColorCardStyle.foreground(for: parsed, over: background)
                let foregroundColor = Color(nsColor: ColorCardStyle.swiftUIColor(for: foreground))

                Rectangle()
                    .fill(Color(nsColor: parsed.nsColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        Text(text)
                            .font(.system(
                                size: compact ? 14 : 17,
                                weight: .semibold,
                                design: .monospaced
                            ))
                            .foregroundStyle(foregroundColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        (foreground == .black ? Color.white : Color.black)
                                            .opacity(0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            } else {
                fallbackPreview
            }
```

- [ ] **Step 3: Delete the obsolete views**

Delete the entire `header`, `metadata`, and `actionRow` computed properties and the `actionButton` helper from `ItemCard.swift`. Keep `relativeTime`, `preview`, `fallbackPreview`, and the full `contextMenu`.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -scheme Clipshot build
```

Expected: `BUILD SUCCEEDED`. If it fails, check that every `CardFooter` closure name matches the existing `ItemCard` stored closures exactly.

- [ ] **Step 5: Commit**

```bash
git add Clipshot/UI/ItemCard.swift
git commit -m "Rebuild ItemCard around the app band and footer"
```

---

## Task 5: Apply the new height and compact threshold

**Files:**
- Modify: `Clipshot/UI/OverlayController.swift`
- Modify: `Clipshot/Services/AppSettings.swift`

- [ ] **Step 1: Update the overlay threshold and fallback**

In `Clipshot/UI/OverlayController.swift`:

```swift
    static let compactThreshold: CGFloat = CardChromeStyle.fullOverlayMinimum
```

and:

```swift
    private var currentHeight: CGFloat {
        guard let appState else { return 460 }
        return CGFloat(appState.settings.overlayHeight)
    }
```

- [ ] **Step 2: Update the default overlay height**

In `Clipshot/Services/AppSettings.swift`, change:

```swift
        self.overlayHeight = defaults.object(forKey: Keys.overlayHeight) as? Double ?? 260
```

to:

```swift
        self.overlayHeight = defaults.object(forKey: Keys.overlayHeight) as? Double ?? 460
```

- [ ] **Step 3: Build and run the full suite**

Run:

```bash
xcodebuild -scheme Clipshot build
xcodebuild -scheme Clipshot test
```

Expected: `BUILD SUCCEEDED`; all tests pass. The new `CardChromeStyleTests` adds 4 tests to the previous 140, so expect **144 tests, 0 failures**.

- [ ] **Step 4: Commit**

```bash
git add Clipshot/UI/OverlayController.swift Clipshot/Services/AppSettings.swift
git commit -m "Use taller full-card default and compact threshold"
```

---

## Task 6: Verify visually and document

**Files:**
- Modify: `TESTING.md`
- Create: `Docs/verify-card-restyle.png`

- [ ] **Step 1: Update the test count and card checklist**

In `TESTING.md`:

- Change the recorded total from `140` to `144` and add `CardChromeStyleTests — 4`.
- Add a “Card chrome” manual section:

```markdown
### Card chrome (Paste-style)

- [ ] Full-height overlay (460 pt): every card shows a 40 px source-app icon in a per-app tinted band at the top, the app name, and `TYPE · time`.
- [ ] The bottom app-metadata row is gone; the footer is always visible with copy, paste, pin, and overflow icons.
- [ ] Selecting another card does not shift the footer or content (no layout jump).
- [ ] Color cards show the same per-app band above a full-bleed parsed-color swatch; the value text remains readable.
- [ ] URL cards paint the raw URL first; the OG image/title/description enrich the card afterward.
- [ ] Full layout at ≥450 pt; compact layout below 450 pt or with “Always use compact cards” enabled.
- [ ] Light mode: Notes yellow and Terminal gray bands remain readable.
- [ ] Copy, paste, pin, and every overflow action (plain paste, shorten for URL, QR, paste stack, edit/rename) work.
- [ ] The right-click menu still exposes pinboards and destructive actions.
```

- [ ] **Step 2: Capture the visual evidence**

Use the same offscreen-render harness used by earlier verification, because Screen Recording may not be granted. Add these temporary blocks, then remove them after capture.

In `Clipshot/App/ClipshotApp.swift`, inside `applicationDidFinishLaunching`, after `Self.sharedState?.start()`:

```swift
        if ProcessInfo.processInfo.environment["CLIPSHOT_SHOW_OVERLAY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Self.sharedState?.overlayController.show()
            }
        }
        if let path = ProcessInfo.processInfo.environment["CLIPSHOT_CAPTURE_PATH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                Self.sharedState?.overlayController.debugCapture(to: path)
            }
        }
```

In `Clipshot/UI/OverlayController.swift`, add:

```swift
    func debugCapture(to path: String) {
        guard let view = panel?.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }
```

Also make the temporary run keep the overlay visible by changing the global-click guard to:

```swift
        if globalClickMonitor == nil,
           ProcessInfo.processInfo.environment["CLIPSHOT_KEEP_OVERLAY"] != "1" {
```

Build, then seed a temporary database:

```bash
cd /Users/ernest/projects/clipboard
xcodebuild -scheme Clipshot build
ORIGINAL_HEIGHT=$(defaults read com.ernest.clipshot settings.overlayHeight 2>/dev/null || true)
ORIGINAL_COMPACT=$(defaults read com.ernest.clipshot settings.alwaysCompact 2>/dev/null || true)
defaults write com.ernest.clipshot settings.overlayHeight 460
defaults write com.ernest.clipshot settings.alwaysCompact -bool false
DB="$HOME/Library/Application Support/Clipshot/clipshot.sqlite"
cp "$DB" "$DB.bak"
sqlite3 "$DB" <<'SQL'
DELETE FROM items;
INSERT INTO items(kind,text,title,sourceApp,bundleId,createdAt,isPinned,hash)
VALUES
('url','https://www.apple.com/newsroom/2024/06/introducing-apple-intelligence-for-iphone-ipad-and-mac/','','Safari','com.apple.Safari',strftime('%Y-%m-%d %H:%M:%f','now'),0,'verify-card-url'),
('color','#a51a15','Color #a51a15','Notes','com.apple.Notes',strftime('%Y-%m-%d %H:%M:%f','now'),0,'verify-card-color'),
('text','Paste-style cards should show the app icon at the top.','','Notes','com.apple.Notes',strftime('%Y-%m-%d %H:%M:%f','now'),0,'verify-card-text');
SQL
pkill -f "Clipshot.app/Contents/MacOS/Clipshot" 2>/dev/null || true
rm -f "$HOME/Library/Application Support/Clipshot/clipshot.lock"
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/Build/Products/Debug/Clipshot.app" -maxdepth 6 | head -1)
CLIPSHOT_SHOW_OVERLAY=1 \
CLIPSHOT_KEEP_OVERLAY=1 \
CLIPSHOT_CAPTURE_PATH="$PWD/Docs/verify-card-restyle.png" \
"$APP/Contents/MacOS/Clipshot" &
sleep 9
pkill -f "Clipshot.app/Contents/MacOS/Clipshot" 2>/dev/null || true
cp "$DB.bak" "$DB"
rm -f "$DB-wal" "$DB-shm" "$DB.bak"
if [ -n "$ORIGINAL_HEIGHT" ]; then
  defaults write com.ernest.clipshot settings.overlayHeight "$ORIGINAL_HEIGHT"
else
  defaults delete com.ernest.clipshot settings.overlayHeight 2>/dev/null || true
fi
if [ -n "$ORIGINAL_COMPACT" ]; then
  defaults write com.ernest.clipshot settings.alwaysCompact -bool "$ORIGINAL_COMPACT"
else
  defaults delete com.ernest.clipshot settings.alwaysCompact 2>/dev/null || true
fi
```

Check that `Docs/verify-card-restyle.png` exists and shows the URL, color, and text cards with the band and footer. Do not start or restore the database while the app is running.

Remove the two temporary harness blocks with `edit_file` (do **not** `git checkout` these files; `OverlayController` also contains the compact-threshold change). Rebuild and rerun the tests after removal.

If the overlay was dismissed before capture, relaunch with the same command; the capture fires at 8 seconds after launch.

- [ ] **Step 3: Run the final gate**

```bash
xcodebuild -scheme Clipshot build
xcodebuild -scheme Clipshot test
git diff --check
```

Expected: build succeeds, **144 tests, 0 failures**, no whitespace errors.

- [ ] **Step 4: Confirm the working tree is clean of debug code**

```bash
grep -RIn "CLIPSHOT_SHOW_OVERLAY\|CLIPSHOT_KEEP_OVERLAY\|debugCapture\|ClipshotTiming" Clipshot || true
git status --short
```

Expected: no debug-hook matches; only the intended source/docs changes plus the auto-managed taste file and untracked `FOLLOWUP-*.md` files, which must not be staged.

- [ ] **Step 5: Commit**

```bash
git add TESTING.md Docs/verify-card-restyle.png
git commit -m "Document and verify the card restyle"
```

---

## Final acceptance checklist

- [ ] Source-app icon is 40 px and top-left, inside a per-app accent band, on every card.
- [ ] Band shows app name and `TYPE · relative time`; old header and bottom metadata row are gone.
- [ ] Persistent footer shows copy, clipboard-paste, pushpin, and overflow.
- [ ] Color cards use the source-app band and full-bleed parsed-color body.
- [ ] URL cards keep raw-URL-first and asynchronous OG enrichment.
- [ ] Card width remains 360 pt; default overlay height 460; compact below 450.
- [ ] Selection does not change layout.
- [ ] Build and full test suite pass; screenshot evidence exists.
- [ ] No debug hooks or verification-only files are committed.
