import SwiftUI

/// One line of the ⌘T bar or of the sidebar address field's suggestions.
enum OmniboxResult: Identifiable {
    case tab(BrowserTab), favorite(Favorite), history(HistoryEntry), action(BrowserAction), go(URL), search(String), suggestion(String)

    var id: String {
        switch self {
        case .tab(let t): "tab-\(t.id)"
        case .favorite(let f): "fav-\(f.id)"
        case .history(let h): "history-\(h.id)"
        case .action(let a): "action-\(a.id)"
        case .go(let u): "go-\(u)"
        case .search(let q): "search-\(q)"
        case .suggestion(let q): "suggestion-\(q)"
        }
    }

    /// The page this result opens, if it is one.
    var pageURL: URL? {
        switch self {
        case .tab(let t): t.url
        case .favorite(let f): f.url
        case .history(let h): h.url
        case .go(let u): u
        case .action, .search, .suggestion: nil
        }
    }
}

/// What the ⌘T bar and the address field have in common: finding results and search suggestions.
enum Omnibox {
    /// Where results come from. The ⌘T bar finds actions and, with nothing typed, open tabs
    /// and recent pages; the address field is about addresses and searches.
    struct Sources {
        var actions = true
        var tabLimit = 5
        var recentWhenEmpty = true

        static let commandBar = Sources()
        static let addressField = Sources(actions: false, tabLimit: 3, recentWhenEmpty: false)
    }

    /// Results for `query`, best first. Searching history goes through up to 20,000 pages, so
    /// this runs when the query or suggestions change, not on every redraw.
    @MainActor static func results(for query: String, sources: Sources, store: BrowserStore, pool: PagePool,
                                   suggestions: [String], suggestionsQuery: String) -> [OmniboxResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let space = store.selectedSpace else { return [] }
        var out: [OmniboxResult] = []
        if let url = url(from: q) { out.append(.go(url)) }
        // While splitting, only pages make sense.
        if sources.actions, store.pendingSplitTabID == nil, !q.isEmpty {
            out += BrowserAction.matching(q).prefix(3).map(OmniboxResult.action)
        }
        let lower = q.lowercased()
        let tabs = space.tabs.filter { lower.isEmpty || $0.title.lowercased().contains(lower) || $0.url.absoluteString.lowercased().contains(lower) }
        out += tabs.prefix(sources.tabLimit).map(OmniboxResult.tab)
        let favs = space.favorites.filter { !lower.isEmpty && $0.title.lowercased().contains(lower) }
        out += favs.prefix(3).map(OmniboxResult.favorite)
        // Pages already open as a tab or favorite show up above instead.
        let open = Set(space.tabs.map(\.url) + space.favorites.map(\.url))
        if !lower.isEmpty {
            let visited = pool.history.search(q, profileID: space.profileID, limit: 12).filter { !open.contains($0.url) }
            out += visited.prefix(5).map(OmniboxResult.history)
        } else if sources.recentWhenEmpty, !store.isPrivate {
            let openSites = Set(open.map(History.site(of:)))
            out += pool.history.history.recentSites(profileID: space.profileID, excluding: openSites, limit: 4).map(OmniboxResult.history)
        }
        if !q.isEmpty {
            out.append(.search(q))
            if suggestionsQuery == q { out += suggestions.filter { $0 != q }.map(OmniboxResult.suggestion) }
        }
        return out
    }

    /// The search engine's suggestions for `query` once typing pauses, or nil if typing went on
    /// (the caller's task was cancelled). Addresses, and private windows, don't ask.
    static func suggestions(for query: String, isPrivate: Bool) async -> [String]? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isPrivate, url(from: q) == nil else { return [] }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return nil }
        let fetched = await SearchSuggestions.fetch(q)
        return Task.isCancelled ? nil : fetched
    }

    /// Treats "example.com" or a full URL as an address; anything with spaces is a search.
    static func url(from text: String) -> URL? {
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        guard text.contains("."), let url = URL(string: "https://\(text)"), url.host() != nil else { return nil }
        return url
    }

    /// The address a result goes to when it replaces the current page, if it isn't a tab switch.
    static func destination(of result: OmniboxResult) -> URL? {
        switch result {
        case .history(let entry): entry.url
        case .go(let url): url
        case .search(let q), .suggestion(let q): SearchEngine.current().url(searching: q)
        case .tab, .favorite, .action: nil
        }
    }
}

/// A result as a row: an icon tile, a title with the address under it, and what picking it
/// does. The highlighted row fills with the space's color, as in Arc.
struct OmniboxRow: View {
    let result: OmniboxResult
    let isHighlighted: Bool
    let accent: Color
    /// The sidebar's address field is narrow: smaller rows, no action label.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            icon
                .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
                .background {
                    RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                        .fill(isHighlighted ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.primary.opacity(0.06)))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .lineLimit(1)
                if let subtitle, !compact || !isSearch {
                    Text(subtitle)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if !compact {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                if isHighlighted {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 18)
                        .background(.white.opacity(0.22), in: .rect(cornerRadius: 5))
                }
            }
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, compact ? 7 : 10)
        .frame(height: compact ? 36 : 48)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous).fill(accent.gradient)
            }
        }
        .contentShape(.rect)
    }

    private var isSearch: Bool {
        if case .search = result { return true }
        if case .suggestion = result { return true }
        return false
    }

    @ViewBuilder private var icon: some View {
        let symbolSize: CGFloat = compact ? 11 : 13
        switch result {
        case .tab(let tab): FaviconView(url: tab.url, size: compact ? 14 : 16)
        case .favorite(let fav): FaviconView(url: fav.url, size: compact ? 14 : 16)
        case .history(let entry): FaviconView(url: entry.url, size: compact ? 14 : 16)
        case .action(let action): Image(systemName: action.symbol).font(.system(size: symbolSize, weight: .medium))
        case .go: Image(systemName: "globe").font(.system(size: symbolSize, weight: .medium))
        case .search, .suggestion: Image(systemName: "magnifyingglass").font(.system(size: symbolSize, weight: .medium))
        }
    }

    private var title: String {
        switch result {
        case .tab(let tab): tab.title.isEmpty ? (tab.url.host() ?? tab.url.absoluteString) : tab.title
        case .favorite(let fav): fav.title
        case .history(let entry): entry.title.isEmpty ? (entry.url.host() ?? entry.url.absoluteString) : entry.title
        case .action(let action): action.title
        case .go(let url): Self.displayAddress(url)
        case .search(let q), .suggestion(let q): q
        }
    }

    private var subtitle: String? {
        switch result {
        case .tab(let tab): Self.displayAddress(tab.url)
        case .favorite(let fav): Self.displayAddress(fav.url)
        case .history(let entry): Self.displayAddress(entry.url)
        case .action, .go: nil
        case .search, .suggestion: SearchEngine.current().title
        }
    }

    private var detail: String {
        switch result {
        case .tab: "Switch to Tab"
        case .favorite: "Favorite"
        case .history: "Open"
        case .action: "Run"
        case .go: "Open"
        case .search: "Search"
        case .suggestion: "Search"
        }
    }

    /// "example.com/path" without the scheme or a lone trailing slash.
    static func displayAddress(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
