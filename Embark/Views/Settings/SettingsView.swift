import AppKit
import SwiftUI

/// Embark ▸ Settings (⌘,). Built like a browser window: a sidebar of pages on the current
/// space's theme, and the page on a card beside it.
struct SettingsView: View {
    @Environment(BrowserStore.self) private var store
    @AppStorage(PreferenceKey.settingsPane) private var pane = SettingsPane.general
    @State private var search = ""
    /// A row picked from search, lit up briefly once its page shows.
    @State private var highlighted: String?

    var body: some View {
        let theme = store.selectedSpace?.resolvedTheme ?? SpaceTheme(tint: .blue)
        HStack(spacing: 0) {
            SettingsSidebar(pane: $pane, search: $search, onPick: pick)
                .frame(width: 224)
            page(pane)
                .id(pane)
                .environment(\.settingsHighlight, highlighted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.92))
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding([.vertical, .trailing], 8)
                .transition(.opacity)
        }
        // Flexible height: once the content runs under the title bar, the window is a title
        // bar taller than it was laid out for, and a fixed height leaves a band at the bottom.
        .frame(width: 880)
        .frame(minHeight: 640, idealHeight: 640, maxHeight: .infinity)
        .background { ThemeBackground(theme: theme) }
        .ignoresSafeArea()
        .background(SettingsWindowStyler())
        .animation(.snappy(duration: 0.2), value: pane)
    }

    @ViewBuilder
    private func page(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .profiles: ProfilesSettings()
        case .passwords: PasswordsSettings()
        case .privacy: PrivacySettings()
        case .shortcuts: ShortcutsSettings()
        case .updates: UpdatesSettings()
        case .about: AboutSettings()
        }
    }

    private func pick(_ item: SettingsSearch.Item) {
        pane = item.pane
        highlighted = item.title
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if highlighted == item.title { withAnimation(.easeOut(duration: 0.5)) { highlighted = nil } }
        }
    }
}

/// Opens Settings on a given page, for “Edit Profiles…” and the like.
extension OpenSettingsAction {
    @MainActor
    func callAsFunction(_ pane: SettingsPane) {
        UserDefaults.standard.set(pane.rawValue, forKey: PreferenceKey.settingsPane)
        callAsFunction()
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var pane: SettingsPane
    @Binding var search: String
    let onPick: (SettingsSearch.Item) -> Void
    @Namespace private var namespace
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights, which float over the sidebar as in the browser window.
            Color.clear.frame(height: 40)

            searchField
                .padding(.bottom, 14)

            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 2) {
                    ForEach(SettingsPane.allCases.filter { !$0.isFooter }) { row($0) }
                }
                Spacer()
                VStack(spacing: 2) {
                    ForEach(SettingsPane.allCases.filter(\.isFooter)) { row($0) }
                }
            } else {
                results
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.18), value: pane)
        .animation(.snappy(duration: 0.18), value: search.isEmpty)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let first = SettingsSearch.matches(search).first { choose(first) } }
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
        .onExitCommand { search = ""; searchFocused = false }
    }

    private func row(_ item: SettingsPane) -> some View {
        SidebarPaneRow(pane: item, isSelected: pane == item, namespace: namespace) {
            pane = item
        }
    }

    @ViewBuilder
    private var results: some View {
        let matches = SettingsSearch.matches(search)
        if matches.isEmpty {
            Text("No settings match “\(search)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { item in
                        SearchResultRow(item: item) { choose(item) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func choose(_ item: SettingsSearch.Item) {
        onPick(item)
        search = ""
        searchFocused = false
    }
}

private struct SidebarPaneRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SettingsIconTile(pane: pane, size: 22)
            Text(pane.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .background {
            // A lit pane of glass behind the row. Drawn as a fill rather than a glassEffect,
            // which in a container composites over the row's icon and title.
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .matchedGeometryEffect(id: "selected-pane", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.14))
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { action() }
    }
}

private struct SearchResultRow: View {
    let item: SettingsSearch.Item
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SettingsIconTile(pane: item.pane, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(item.pane.title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            if hovering { RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.18)) }
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
    }
}

/// A page's icon: a white symbol on a rounded tile of its colors, as in System Settings.
struct SettingsIconTile: View {
    let pane: SettingsPane
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: pane.colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            }
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: pane.colors.last!.opacity(0.3), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Window

/// Lets the sidebar run up under the traffic lights, as in the browser window. The Settings
/// scene has no window style of its own, so this sets it on the window directly.
private struct SettingsWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class StylerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.toolbar = nil
        }
    }
}
