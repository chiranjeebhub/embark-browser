import SwiftUI

/// ⌘T / ⌘L: one glass bar that switches tabs, opens favorites or pages from history, runs
/// actions like New Window, or goes to a URL or search.
struct CommandBar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private enum Result: Identifiable {
        case tab(BrowserTab), favorite(Favorite), history(HistoryEntry), action(BrowserAction), go(URL), search(String)

        var id: String {
            switch self {
            case .tab(let t): "tab-\(t.id)"
            case .favorite(let f): "fav-\(f.id)"
            case .history(let h): "history-\(h.id)"
            case .action(let a): "action-\(a.id)"
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
        // While splitting, only pages make sense.
        if store.pendingSplitTabID == nil { out += BrowserAction.matching(q).prefix(3).map(Result.action) }
        let lower = q.lowercased()
        let tabs = space.tabs.filter { lower.isEmpty || $0.title.lowercased().contains(lower) || $0.url.absoluteString.lowercased().contains(lower) }
        out += tabs.prefix(5).map(Result.tab)
        let favs = space.favorites.filter { !lower.isEmpty && $0.title.lowercased().contains(lower) }
        out += favs.prefix(3).map(Result.favorite)
        if !lower.isEmpty {
            // Pages already open as a tab or favorite show up above instead.
            let open = Set(space.tabs.map(\.url) + space.favorites.map(\.url))
            let visited = pool.history.search(q, profileID: space.profileID, limit: 12).filter { !open.contains($0.url) }
            out += visited.prefix(5).map(Result.history)
        }
        if !q.isEmpty { out.append(.search(q)) }
        return out
    }

    var body: some View {
        // Sits over the page area; the field starts near its middle and results grow downward.
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).onTapGesture { close() }
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
                .frame(width: min(640, geo.size.width - 48))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.top, max(24, geo.size.height * 0.5 - 37))
            }
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
            case .history(let entry):
                FaviconView(url: entry.url, size: 22)
                label(entry.title, detail: entry.url.host() ?? "History")
            case .action(let action):
                Image(systemName: action.symbol).frame(width: 22)
                label(action.title, detail: "Action")
            case .go(let url):
                Image(systemName: "globe").frame(width: 22)
                label(url.absoluteString, detail: "Open")
            case .search(let q):
                Image(systemName: "magnifyingglass").frame(width: 22)
                label("Search for \u{201C}\(q)\u{201D}", detail: SearchEngine.current().title)
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
        let splitTarget = store.pendingSplitTabID
        switch all[index] {
        case .tab(let tab): store.selectTab(tab.id)
        case .favorite(let fav): store.selectFavorite(fav.id)
        case .history(let entry): store.openTab(entry.url, title: entry.title)
        case .action(let action):
            close()
            run(action)
            return
        case .go(let url): store.openTab(url)
        case .search(let q):
            if let url = SearchEngine.current().url(searching: q) { store.openTab(url) }
        }
        // New Split: whatever was picked becomes a pane beside the tab it started from.
        if let splitTarget, let picked = store.selectedTab?.id, picked != splitTarget {
            store.addToSplit(picked, beside: splitTarget)
        }
        close()
    }

    private func run(_ action: BrowserAction) {
        let tabID = store.selectedTab?.id
        let page = pool.existingPage(for: tabID)
        switch action {
        case .newWindow: openWindow(id: "browser")
        case .newPrivateWindow: openWindow(id: "private")
        case .newSpace: store.isCreatingSpace = true
        case .newFolder: store.addFolder()
        case .newSplit: store.startNewSplit()
        case .addToFavorites: if let tab = store.selectedTab { store.addFavorite(from: tab) }
        case .copyURL:
            guard let url = store.selectedTab?.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case .reload: page?.reload()
        case .closeTab: if let tabID { pool.close(tabID); store.closeTab(tabID) }
        case .reopenClosedTab: store.reopenLastClosedTab()
        case .findOnPage: if let tabID { pool.openFind(in: tabID) }
        case .zoomIn: pool.zoom(tabID, Zoom.zoomedIn)
        case .zoomOut: pool.zoom(tabID, Zoom.zoomedOut)
        case .actualSize: pool.zoom(tabID) { _ in 1 }
        case .print: page?.print()
        case .developerTools: page?.showDevTools()
        case .showHistory, .clearHistory: openWindow(id: "history")
        case .toggleSidebar: withAnimation(.sidebar) { store.isSidebarVisible.toggle() }
        case .settings: openSettings()
        }
    }

    private func close() {
        store.pendingSplitTabID = nil
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
