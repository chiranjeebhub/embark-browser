import SwiftUI

/// ⌘T / ⌘L: one glass bar that switches tabs, opens favorites, or goes to a URL or search.
struct CommandBar: View {
    @Environment(BrowserStore.self) private var store
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private enum Result: Identifiable {
        case tab(BrowserTab), favorite(Favorite), go(URL), search(String)

        var id: String {
            switch self {
            case .tab(let t): "tab-\(t.id)"
            case .favorite(let f): "fav-\(f.id)"
            case .go(let u): "go-\(u)"
            case .search(let q): "search-\(q)"
            }
        }
    }

    private var results: [Result] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let space = store.selectedSpace else { return [] }
        var out: [Result] = []
        if let url = Self.url(from: q) { out.append(.go(url)) }
        let lower = q.lowercased()
        let tabs = space.tabs.filter { lower.isEmpty || $0.title.lowercased().contains(lower) || $0.url.absoluteString.lowercased().contains(lower) }
        out += tabs.prefix(5).map(Result.tab)
        let favs = space.favorites.filter { !lower.isEmpty && $0.title.lowercased().contains(lower) }
        out += favs.prefix(3).map(Result.favorite)
        if !q.isEmpty { out.append(.search(q)) }
        return out
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search tabs, or type a URL", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .focused($focused)
                        .onSubmit { activate(highlighted) }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(.white.opacity(0.5), in: .rect(cornerRadius: 16))

                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    row(result, highlighted: index == highlighted)
                        .onTapGesture { activate(index) }
                }
            }
            .padding(10)
            .frame(width: 640)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.top, 120)
        }
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    @ViewBuilder private func row(_ result: Result, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            switch result {
            case .tab(let tab):
                FaviconView(url: tab.url, size: 22)
                label(tab.title, detail: "Switch to tab")
            case .favorite(let fav):
                FaviconView(url: fav.url, size: 22)
                label(fav.title, detail: "Favorite")
            case .go(let url):
                Image(systemName: "globe").frame(width: 22)
                label(url.absoluteString, detail: "Open")
            case .search(let q):
                Image(systemName: "magnifyingglass").frame(width: 22)
                label("Search for \u{201C}\(q)\u{201D}", detail: "Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(highlighted ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }

    private func label(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func activate(_ index: Int) {
        let all = results
        guard all.indices.contains(index) else { return }
        switch all[index] {
        case .tab(let tab): store.selectTab(tab.id)
        case .favorite(let fav): store.openFavorite(fav)
        case .go(let url): store.openTab(url)
        case .search(let q):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: q)]
            if let url = components.url { store.openTab(url) }
        }
        close()
    }

    private func close() {
        store.isCommandBarOpen = false
    }

    /// Treats "example.com" or a full URL as an address; anything with spaces is a search.
    static func url(from text: String) -> URL? {
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        guard text.contains("."), let url = URL(string: "https://\(text)"), url.host() != nil else { return nil }
        return url
    }
}
