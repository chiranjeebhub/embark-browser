import SwiftUI

/// The puzzle button in the address bar. Like Arc, it opens a popover with the profile's pinned
/// extensions as tiles and the rest in a list; clicking one shows its popup in place.
/// Extensions belong to the profile, so spaces sharing a profile share them.
struct ExtensionsButton: View {
    let profile: Profile
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "puzzlepiece.extension").font(.system(size: 13))
        }
        .help("Extensions")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ExtensionsPopover(profile: profile, isPresented: $isPresented)
        }
    }
}

private struct ExtensionsPopover: View {
    let profile: Profile
    @Binding var isPresented: Bool
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var extensions: [InstalledExtension] = []
    /// The extension whose popup is showing.
    @State private var opened: InstalledExtension?

    private static let webStore = URL(string: "https://chromewebstore.google.com")!

    private var pinnedIDs: [String] { store.profiles.first { $0.id == profile.id }?.pinnedExtensionIDs ?? [] }
    private var pinned: [InstalledExtension] { pinnedIDs.compactMap { id in extensions.first { $0.id == id } } }
    private var unpinned: [InstalledExtension] { extensions.filter { !pinnedIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let opened, let url = opened.popupURL {
                popup(opened, url: url)
            } else {
                list
            }
        }
        .padding(.vertical, 10)
        // Chromium writes newly installed extensions to disk a few seconds later, so read on every open.
        .onAppear { extensions = pool.extensions(for: profile) }
        .animation(.snappy(duration: 0.2), value: opened)
    }

    // MARK: Screens

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extensions").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Manage") { open(URL(string: "chrome://extensions")!, title: "Extensions") }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 14)

            if extensions.isEmpty {
                Text("Extensions you add from the Chrome Web Store show up here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }

            if !pinned.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(pinned) { ext in
                        Button { activate(ext) } label: { ExtensionTile(ext: ext) }
                            .buttonStyle(ExtensionItemStyle(cornerRadius: 10, resting: 0.05))
                            .help(ext.name)
                            .contextMenu { menu(for: ext, pinned: true) }
                    }
                }
                .padding(.horizontal, 12)
            }

            if !unpinned.isEmpty {
                if !pinned.isEmpty { Divider().padding(.horizontal, 12) }
                VStack(spacing: 0) {
                    ForEach(unpinned) { ext in
                        ExtensionRow(ext: ext, activate: { activate(ext) },
                                     pin: { store.setExtension(ext.id, pinned: true, in: profile.id) })
                            .contextMenu { menu(for: ext, pinned: false) }
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider().padding(.horizontal, 12)
            Button { open(Self.webStore, title: "Chrome Web Store") } label: {
                Label("Add from Chrome Web Store", systemImage: "plus")
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
        }
        .frame(width: 300)
    }

    private func popup(_ ext: InstalledExtension, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { opened = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("All extensions")
                ExtensionIcon(ext: ext, size: 16)
                Text(ext.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
            }
            .padding(.horizontal, 14)
            // Popups size themselves in Chrome; a CEF child view can't report its content size,
            // so it gets Chrome's usual popup size.
            ExtensionPopupView(url: url, profile: profile)
                .frame(width: 380, height: 520)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
        }
        .id(ext.id)
    }

    @ViewBuilder
    private func menu(for ext: InstalledExtension, pinned: Bool) -> some View {
        Button(pinned ? "Unpin" : "Pin") { store.setExtension(ext.id, pinned: !pinned, in: profile.id) }
        if let options = ext.optionsURL {
            Button("Options") { open(options, title: ext.name) }
        }
        Button("Manage Extension") { open(manageURL(ext), title: ext.name) }
    }

    // MARK: Actions

    /// Shows the popup; an extension without one opens its options, and a disabled one its
    /// page in chrome://extensions so it can be turned on.
    private func activate(_ ext: InstalledExtension) {
        if !ext.isEnabled {
            open(manageURL(ext), title: ext.name)
        } else if ext.popupURL != nil {
            opened = ext
        } else {
            open(ext.optionsURL ?? manageURL(ext), title: ext.name)
        }
    }

    private func manageURL(_ ext: InstalledExtension) -> URL {
        URL(string: "chrome://extensions/?id=\(ext.id)")!
    }

    private func open(_ url: URL, title: String) {
        isPresented = false
        store.openTab(url, title: title)
    }
}

// MARK: - Pieces

private struct ExtensionTile: View {
    let ext: InstalledExtension

    var body: some View {
        VStack(spacing: 5) {
            ExtensionIcon(ext: ext, size: 24)
            Text(ext.name)
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .opacity(ext.isEnabled ? 1 : 0.45)
    }
}

private struct ExtensionRow: View {
    let ext: InstalledExtension
    let activate: () -> Void
    let pin: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: activate) {
                HStack(spacing: 10) {
                    ExtensionIcon(ext: ext, size: 18)
                    Text(ext.name).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    if !ext.isEnabled {
                        Text("Off").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .opacity(ext.isEnabled ? 1 : 0.55)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: pin) { Image(systemName: "pin").font(.system(size: 12)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Pin")
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(hovering ? 0.06 : 0)))
        .onHover { hovering = $0 }
    }
}

/// The extension's own icon, else its initial on a tile.
private struct ExtensionIcon: View {
    let ext: InstalledExtension
    let size: CGFloat

    var body: some View {
        if let file = ext.iconFile, let image = NSImage(contentsOf: file) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(.secondary.opacity(0.3))
                .frame(width: size, height: size)
                .overlay {
                    Text(ext.name.prefix(1).uppercased())
                        .font(.system(size: size * 0.55, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct ExtensionItemStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let resting: Double

    func makeBody(configuration: Configuration) -> some View {
        Item(configuration: configuration, cornerRadius: cornerRadius, resting: resting)
    }

    private struct Item: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let resting: Double
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.primary.opacity(configuration.isPressed ? resting + 0.08 : hovering ? resting + 0.04 : resting))
                }
                .contentShape(.rect)
                .onHover { hovering = $0 }
        }
    }
}

/// An extension's popup page, alive while it is shown.
private struct ExtensionPopupView: NSViewRepresentable {
    let url: URL
    let profile: Profile
    @Environment(PagePool.self) private var pool

    final class Coordinator {
        var page: BrowserPage?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        let page = pool.makeExtensionPopup(url, profile: profile)
        page.view.frame = container.bounds
        page.view.autoresizingMask = [.width, .height]
        container.addSubview(page.view)
        context.coordinator.page = page
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.page?.close()
        coordinator.page = nil
    }
}
