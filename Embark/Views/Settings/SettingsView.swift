import AppKit
import SwiftUI

extension PreferenceKey {
    /// The Settings page that was open last, so ⌘, comes back to it.
    static let settingsPane = "settingsPane"
}

/// One page of Settings. To add a page, add a case here, its look below, and its view in
/// `SettingsView.page(_:)`; its rows go in `SettingsSearch.index` so search finds them.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, profiles, passwords, privacy, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .profiles: "Profiles"
        case .passwords: "Passwords"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        case .about: "About Embark"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Your default browser, search, tabs and links from other apps."
        case .appearance: "How the sidebar looks and where it sits."
        case .profiles: "Separate logins, cookies, history and extensions."
        case .passwords: "Logins saved in your Mac’s Keychain."
        case .privacy: "Cookies, sign-ins and what sites can use."
        case .shortcuts: "Everything you can do from the keyboard."
        case .about: "Open source, made for the Mac."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .profiles: "person.2.fill"
        case .passwords: "key.fill"
        case .privacy: "hand.raised.fill"
        case .shortcuts: "command"
        case .about: "sailboat.fill"
        }
    }

    /// The icon tile's gradient, top to bottom.
    var colors: [Color] {
        switch self {
        case .general: [Color(white: 0.62), Color(white: 0.42)]
        case .appearance: [Color(red: 1, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.32, blue: 0.95)]
        case .profiles: [Color(red: 0.3, green: 0.7, blue: 1), Color(red: 0.2, green: 0.42, blue: 0.95)]
        case .passwords: [Color(red: 0.55, green: 0.6, blue: 0.68), Color(red: 0.32, green: 0.36, blue: 0.44)]
        case .privacy: [Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.25, green: 0.3, blue: 0.85)]
        case .shortcuts: [Color(red: 0.42, green: 0.42, blue: 0.48), Color(red: 0.2, green: 0.2, blue: 0.26)]
        case .about: [Color(red: 0.44, green: 0.48, blue: 1), Color(red: 0.13, green: 0.7, blue: 0.65)]
        }
    }

    /// Shown in the sidebar after a gap, away from the pages you change things on.
    var isFooter: Bool { self == .about }
}

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
        .frame(width: 880, height: 640)
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
                GlassEffectContainer(spacing: 4) {
                    VStack(spacing: 2) {
                        ForEach(SettingsPane.allCases.filter { !$0.isFooter }) { row($0) }
                    }
                }
                Spacer()
                GlassEffectContainer(spacing: 4) {
                    VStack(spacing: 2) {
                        ForEach(SettingsPane.allCases.filter(\.isFooter)) { row($0) }
                    }
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
            if isSelected {
                Color.clear
                    .glassEffect(.regular.tint(.white.opacity(0.4)), in: .rect(cornerRadius: 10))
                    .glassEffectID("selected-pane", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.14))
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(perform: action)
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

// MARK: - Search

/// Every row in Settings, so the sidebar's search can find a setting by what it does.
enum SettingsSearch {
    struct Item: Identifiable {
        let pane: SettingsPane
        /// The row's title, as `SettingRow` shows it, so the row can be lit up.
        let title: String
        var keywords = ""
        var id: String { "\(pane.rawValue) \(title)" }
    }

    static let index: [Item] = [
        Item(pane: .general, title: "Default browser", keywords: "links other apps make default"),
        Item(pane: .general, title: "Search engine", keywords: "google duckduckgo bing brave kagi ecosia perplexity command bar"),
        Item(pane: .general, title: "Archive tabs after", keywords: "auto archive close old tabs library clean up"),
        Item(pane: .general, title: "Open links in Little windows", keywords: "little arc air traffic popup small window links other apps"),
        Item(pane: .general, title: "Import bookmarks", keywords: "chrome brave edge safari html favorites"),
        Item(pane: .appearance, title: "Sidebar position", keywords: "left right side layout"),
        Item(pane: .appearance, title: "Show the address in the sidebar", keywords: "url pill address bar"),
        Item(pane: .appearance, title: "Show the sidebar at the window edge", keywords: "peek hover hidden auto hide"),
        Item(pane: .appearance, title: "New spaces start with", keywords: "theme color gradient space"),
        Item(pane: .profiles, title: "Profiles", keywords: "accounts logins separate work personal name color"),
        Item(pane: .profiles, title: "Extensions", keywords: "chrome web store add-ons plugins"),
        Item(pane: .profiles, title: "Browsing data", keywords: "clear cache cookies history storage"),
        Item(pane: .passwords, title: "Saved passwords", keywords: "logins keychain autofill import export csv"),
        Item(pane: .privacy, title: "Block third-party cookies", keywords: "tracking trackers privacy"),
        Item(pane: .privacy, title: "Start every session signed out", keywords: "clear cookies launch sign out"),
        Item(pane: .privacy, title: "Site permissions", keywords: "camera microphone notifications location sound allow block"),
        Item(pane: .shortcuts, title: "Keyboard shortcuts", keywords: "keys hotkeys command"),
        Item(pane: .about, title: "Version", keywords: "about update license github source report problem"),
    ]

    static func matches(_ query: String) -> [Item] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return [] }
        return index.filter { item in
            let text = "\(item.title) \(item.pane.title) \(item.keywords)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
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
