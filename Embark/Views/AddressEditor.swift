import SwiftUI

/// Where the sidebar's address pill is, so the address editor can open right over it.
struct AddressPillBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    /// During a space swipe both spaces' pills report; the selected space's comes first.
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Clicking the sidebar's address opens this over the pill, as in Arc: the full address,
/// selected so typing replaces it, and suggestions below once you type. Return loads the page
/// in the current tab; ⌘T is still the way to a new one.
struct AddressEditor: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var query: String
    /// The address the editor opened with; suggestions show once the text differs from it.
    private let original: String
    @State private var highlighted = 0
    @State private var suggestions: [String] = []
    @State private var suggestionsQuery = ""
    @State private var results: [OmniboxResult] = []
    @FocusState private var focused: Bool

    init(url: URL?) {
        original = url?.absoluteString ?? ""
        _query = State(initialValue: original)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var showsResults: Bool { !trimmed.isEmpty && query != original && !results.isEmpty }

    var body: some View {
        let accent = store.selectedSpace?.accent ?? .accentColor
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                TextField("Search or Enter URL…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(submit)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            // Lines the text up with the pill's, which sits 4pt inside this card.
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 34)

            if showsResults {
                Divider().opacity(0.6).padding(.horizontal, 6)
                VStack(spacing: 1) {
                    ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { index, result in
                        OmniboxRow(result: result, isHighlighted: index == highlighted, accent: accent, compact: true)
                            .onTapGesture { activate(result) }
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .animation(.snappy(duration: 0.16), value: showsResults)
        .onAppear { focused = true }
        // Clicking the page, or anywhere that takes the keyboard, puts the address back.
        .onChange(of: focused) { _, isFocused in if !isFocused { end() } }
        .onChange(of: store.selectedTab?.id) { end() }
        .onChange(of: store.selectedSpaceID) { end() }
        .onChange(of: query) {
            highlighted = 0
            refresh()
        }
        .onChange(of: suggestions) { refresh() }
        .onChange(of: suggestionsQuery) { refresh() }
        .task(id: query) {
            guard query != original,
                  let fetched = await Omnibox.suggestions(for: query, isPrivate: store.isPrivate) else { return }
            suggestions = fetched
            suggestionsQuery = trimmed
        }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(min(results.count, 8) - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
        .onKeyPress(.escape) { end(); return .handled }
    }

    private func refresh() {
        results = Omnibox.results(for: query, sources: .addressField, store: store, pool: pool,
                                  suggestions: suggestions, suggestionsQuery: suggestionsQuery)
    }

    private func submit() {
        if showsResults, results.indices.contains(highlighted) {
            activate(results[highlighted])
        } else if let url = Omnibox.url(from: trimmed) {
            load(url)
        } else if !trimmed.isEmpty, let url = SearchEngine.current().url(searching: trimmed) {
            load(url)
        } else {
            end()
        }
    }

    private func activate(_ result: OmniboxResult) {
        switch result {
        case .tab(let tab): store.selectTab(tab.id)
        case .favorite(let fav): store.selectFavorite(fav.id)
        default: if let url = Omnibox.destination(of: result) { load(url) }
        }
        end()
    }

    /// Loads `url` in place of the current page. With no page open, it opens a tab.
    private func load(_ url: URL) {
        if let tab = store.selectedTab {
            if let page = pool.existingPage(for: tab.id) {
                page.load(url)
            } else {
                store.updateTab(tab.id, title: nil, url: url)
            }
        } else {
            store.openTab(url)
        }
        end()
    }

    private func end() {
        store.isEditingAddress = false
    }
}
