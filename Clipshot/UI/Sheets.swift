import SwiftUI

struct ShortenSheet: View {
    @ObservedObject var appState: AppState
    let request: ShortenRequest

    @Environment(\.dismiss) private var dismiss
    @State private var slug = ""
    @State private var domain = ""
    @State private var tags = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var backend: ShortenerBackend? {
        appState.activeBackend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(Color.accentColor)
                Text("Shorten link")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if let backend {
                    Text(backend.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }

            Text(request.url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let backend, backend.capabilities.supportsCustomSlug {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom slug").font(.system(size: 11, weight: .medium))
                    TextField("Leave empty for a random slug", text: $slug)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let backend, backend.capabilities.supportsCustomDomain {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Domain").font(.system(size: 11, weight: .medium))
                    TextField("bit.ly", text: $domain)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let backend, backend.capabilities.supportsTags {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags").font(.system(size: 11, weight: .medium))
                    TextField("Comma separated", text: $tags)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !appState.isBackendConfigured {
                    SettingsLink {
                        Text("Open Integrations…")
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSubmitting ? "Shortening…" : "Shorten") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !appState.isBackendConfigured)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear {
            domain = appState.settings.backendDefaultDomain
            tags = appState.settings.backendDefaultTags
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagList = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        Task {
            let error = await appState.shorten(
                item: request.item,
                url: request.url,
                slug: trimmedSlug.isEmpty ? nil : trimmedSlug,
                domain: trimmedDomain.isEmpty ? nil : trimmedDomain,
                tags: tagList
            )
            isSubmitting = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

struct EditorSheet: View {
    @ObservedObject var appState: AppState
    let request: EditorRequest

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var title = ""

    private var heading: String {
        switch request.mode {
        case .newSnippet: return "New text item"
        case .editText: return "Edit item"
        case .rename: return "Rename item"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.system(size: 16, weight: .semibold))

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            if request.mode != .rename {
                TextEditor(text: $text)
                    .font(.system(size: 12))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.15))
                    )
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    appState.saveEditor(request, text: text, title: title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            text = request.item?.text ?? ""
            title = request.item?.title ?? ""
        }
    }
}

struct NewPinboardSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = PinboardPalette.colors[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New pinboard")
                .font(.system(size: 16, weight: .semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(PinboardPalette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .orange)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                        )
                        .onTapGesture { colorHex = hex }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    appState.createPinboard(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: colorHex
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
