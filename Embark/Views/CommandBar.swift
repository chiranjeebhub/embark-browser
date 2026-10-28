import SwiftUI

/// ⌘T / ⌘L: one glass bar that switches tabs, opens favorites or pages from history, runs
/// actions like New Window, or goes to a URL, a search or one of the search engine's suggestions.
struct CommandBar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var highlighted = 0
    /// The engine's suggestions for `suggestionsQuery`.
    @State private var suggestions: [String] = []
    @State private var suggestionsQuery = ""
    /// Worked out when the query or suggestions change, not on every redraw or arrow key.
    @State private var results: [OmniboxResult] = []
    @FocusState private var focused: Bool

    private func matchingResults() -> [OmniboxResult] {
        Omnibox.results(for: query, sources: .commandBar, store: store, pool: pool,
                        suggestions: suggestions, suggestionsQuery: suggestionsQuery)
    }

    /// The field's glyph follows what Return would do.
    private var fieldSymbol: String {
        if store.pendingSplitTabID != nil { return "rectangle.split.2x1" }
        return Omnibox.url(from: query.trimmingCharacters(in: .whitespaces)) == nil ? "magnifyingglass" : "globe"
    }

    var body: some View {
        // Sits over the page area in its upper third, as in Arc; results grow downward.
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.18).onTapGesture { close() }
                panel
                    .frame(width: min(680, geo.size.width - 48))
                    .padding(.top, max(24, geo.size.height * 0.2))
            }
        }
        .onAppear {
            if !store.commandBarSeed.isEmpty {
                query = store.commandBarSeed
                store.commandBarSeed = ""
                Self.moveCaretToEnd()
            }
            store.isEditingAddress = false
            focused = true
            results = matchingResults()
        }
        .onChange(of: query) {
            highlighted = 0
            results = matchingResults()
        }
        .onChange(of: suggestions) { results = matchingResults() }
        .onChange(of: suggestionsQuery) { results = matchingResults() }
        .task(id: query) {
            guard let fetched = await Omnibox.suggestions(for: query, isPrivate: store.isPrivate) else { return }
            suggestions = fetched
            suggestionsQuery = query.trimmingCharacters(in: .whitespaces)
        }
        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private var panel: some View {
        let accent = store.selectedSpace?.accent ?? .accentColor
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: fieldSymbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                TextField(store.pendingSplitTabID == nil ? "Search or Enter URL…" : "Open a page beside this one…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .focused($focused)
                    .onSubmit { activate(highlighted) }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            if !results.isEmpty {
                Divider().opacity(0.6).padding(.horizontal, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if let header = header(before: index) {
                                    Text(header)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.top, index == 0 ? 2 : 8)
                                        .padding(.bottom, 2)
                                }
                                OmniboxRow(result: result, isHighlighted: index == highlighted, accent: accent)
                                    .id(result.id)
                                    .onTapGesture { activate(index) }
                            }
                        }
                        .padding(8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 440)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: highlighted) { _, index in
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }
        }
        .background {
            // Opaque enough to read over any page, still glass at the edges.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        .animation(.snappy(duration: 0.18), value: results.map(\.id))
    }

    /// With nothing typed, the results are the open tabs and then recent pages; each gets a
    /// heading so the list doesn't read as one jumble.
    private func header(before index: Int) -> String? {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let kind: (OmniboxResult) -> String? = { result in
            switch result {
            case .tab: "Open Tabs"
            case .history: "Recently Visited"
            default: nil
            }
        }
        let current = kind(results[index])
        guard let current else { return nil }
        return index == 0 || kind(results[index - 1]) != current ? current : nil
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
        case .search(let q), .suggestion(let q):
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

    /// A field that takes focus selects all its text, so the next key typed would replace
    /// what the new tab page passed on. Puts the caret after it once the field has focus.
    private static func moveCaretToEnd() {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
    }

    private func close() {
        store.pendingSplitTabID = nil
        store.isCommandBarOpen = false
    }
}
