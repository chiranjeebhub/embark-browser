import SwiftUI

struct Sidebar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationRow()
            Group {
                if store.isCreatingSpace {
                    CreateSpaceForm()
                } else if let space = store.selectedSpace {
                    VStack(alignment: .leading, spacing: 14) {
                        AddressPill()
                        FavoritesGrid(favorites: space.favorites)
                        Divider().padding(.horizontal, 8)
                        TabList(space: space)
                    }
                    .padding(.top, 5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            BottomBar()
        }
        // Same side margin as the traffic lights' left inset.
        .padding(.horizontal, Self.margin)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.22), value: store.isCreatingSpace)
    }

    static let margin: CGFloat = 10
}

extension Animation {
    /// Showing and hiding the sidebar should feel instant.
    static let sidebar = Animation.snappy(duration: 0.16)
}

/// Plain SF Symbol buttons as in Arc: no background until hovered.
private struct SidebarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration)
    }

    private struct IconButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 15))
                .foregroundStyle(.primary.opacity(isEnabled ? 0.7 : 0.3))
                .frame(width: SidebarIconButtonStyle.size, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isEnabled && hovering ? (configuration.isPressed ? 0.14 : 0.08) : 0))
                }
                .contentShape(.rect)
                .onHover { hovering = $0 }
        }
    }

    /// Hit area width; glyphs sit about 5pt inside it.
    static let size: CGFloat = 26
}

private struct NavigationRow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        let page = pool.existingPage(for: store.selectedTab?.id)
        let _ = pool.revision
        // Shares the title bar row with the traffic lights, on their center line (15.5pt).
        HStack(spacing: 10) {
            Button { withAnimation(.sidebar) { store.isSidebarVisible.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }
            .help(store.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            Spacer()
            Button { page?.goBack() } label: { Image(systemName: "arrow.left") }
                .disabled(!(page?.canGoBack ?? false))
            Button { page?.goForward() } label: { Image(systemName: "arrow.right") }
                .disabled(!(page?.canGoForward ?? false))
            Button { page?.reload() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(page == nil)
        }
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: 31)
        // The toggle's glyph starts ~12pt after the last traffic light (which ends at ~67pt);
        // reload's glyph ends on the URL pill's right edge.
        .padding(.leading, 64)
        .padding(.trailing, -5)
    }
}

/// The current page's address, flat like Arc's: host only, with copy and page actions.
private struct AddressPill: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.colorScheme) private var colorScheme
    @State private var justCopied = false
    @State private var showsPageInfo = false
    @State private var showsSiteSettings = false

    var body: some View {
        let url = store.selectedTab?.url
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                if let url {
                    Text(url.host() ?? url.absoluteString).lineLimit(1)
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 12))
                    Text("Search or Enter URL…").lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onTapGesture { store.isCommandBarOpen = true }

            if let url {
                if justCopied {
                    Text("Copied").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Button { copy(url) } label: { Image(systemName: "link").font(.system(size: 13)) }
                        .help("Copy URL")
                }
                Button { showsPageInfo = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                }
                .help("Page info")
                .popover(isPresented: $showsPageInfo, arrowEdge: .bottom) {
                    if let tab = store.selectedTab {
                        PageInfoPopover(tab: tab, isPresented: $showsPageInfo, showsSiteSettings: $showsSiteSettings)
                            .id(tab.id)
                    }
                }
                .sheet(isPresented: $showsSiteSettings) {
                    if let tab = store.selectedTab { SiteSettingsSheet(tab: tab) }
                }
            }
        }
        .buttonStyle(SidebarIconButtonStyle())
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9.5).fill(colorScheme == .dark ? .white.opacity(0.11) : .black.opacity(0.05)))
        .animation(.snappy(duration: 0.15), value: justCopied)
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }
}

/// What a drag inside the sidebar carries. Sent as a plain string so no custom type needs
/// registering; anything else dropped on the sidebar is ignored.
enum SidebarDrag: Equatable {
    case tab(BrowserTab.ID)
    case favorite(Favorite.ID)
    case split(Split.ID)

    /// The drag in progress, so drop targets can show its placeholder while hovering. Drops
    /// themselves trust only the dragged string, since this can be stale after a cancelled drag.
    @MainActor static var current: SidebarDrag?

    var token: String {
        switch self {
        case .tab(let id): "embark-tab:\(id.uuidString)"
        case .favorite(let id): "embark-favorite:\(id.uuidString)"
        case .split(let id): "embark-split:\(id.uuidString)"
        }
    }

    /// Tabs and favorites can become split panes; a whole split can't.
    var canSplit: Bool {
        if case .split = self { false } else { true }
    }

    init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "embark-tab": self = .tab(id)
        case "embark-favorite": self = .favorite(id)
        case "embark-split": self = .split(id)
        default: return nil
        }
    }

    @MainActor func url(in space: Space) -> URL? {
        switch self {
        case .tab(let id): space.tabs.first { $0.id == id }?.url
        case .favorite(let id): space.favorites.first { $0.id == id }?.url
        case .split(let id):
            space.splits?.first { $0.id == id }.flatMap { split in space.tabs.first { $0.id == split.tabIDs.first }?.url }
        }
    }

    /// Starts dragging this item; used with `.onDrag`. Pages stop taking drops until the drag
    /// ends, so it can land on the page area to make a split.
    @MainActor func itemProvider(pool: PagePool) -> NSItemProvider {
        Self.current = self
        pool.suspendPageDrops()
        return NSItemProvider(object: token as NSString)
    }

    /// Reads the dragged string, then runs `apply` on the main actor with the item it names
    /// (nil for anything that isn't a sidebar item).
    static func load(from info: DropInfo, then apply: @escaping @MainActor (SidebarDrag?) -> Void) -> Bool {
        guard let provider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        nonisolated(unsafe) let apply = apply
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let token = (object as? NSString).map(String.init)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { apply(token.flatMap(SidebarDrag.init(token:))) }
            }
        }
        return true
    }
}

extension Animation {
    /// Items sliding aside for a drop placeholder.
    static let dropReflow = Animation.snappy(duration: 0.2)
}

/// Where a dragged item would land, drawn as an empty tile or row in its place.
private struct DropPlaceholder: View {
    let url: URL?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.white.opacity(0.08))
            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay { if let url { FaviconView(url: url, size: 22).opacity(0.35) } }
    }
}

/// Each space's own favorites. These are its pinned sites; there is no separate pinned list.
/// Drag a tab here to pin it, or a favorite out to the tab list to unpin it. While something
/// is dragged over the grid, a placeholder tile opens at the drop spot, as in Arc.
private struct FavoritesGrid: View {
    let favorites: [Favorite]
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    /// The placeholder's index among the tiles, while a drag hovers the grid.
    @State private var placeholder: Int?
    @State private var width: CGFloat = 0

    private static let columns = 4
    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 48

    private enum Slot: Identifiable {
        case favorite(Favorite), placeholder
        var id: String {
            switch self {
            case .favorite(let favorite): favorite.id.uuidString
            case .placeholder: "placeholder"
            }
        }
    }

    /// Favorites other than the one being dragged, which gives up its slot to the placeholder.
    private var staying: [Favorite] {
        favorites.filter { placeholder == nil || SidebarDrag.current != .favorite($0.id) }
    }

    private var slots: [Slot] {
        var slots = staying.map(Slot.favorite)
        if let placeholder { slots.insert(.placeholder, at: min(placeholder, slots.count)) }
        return slots
    }

    var body: some View {
        GlassEffectContainer(spacing: Self.spacing) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns),
                      spacing: Self.spacing) {
                ForEach(slots) { slot in
                    switch slot {
                    case .favorite(let favorite): tile(favorite)
                    case .placeholder:
                        DropPlaceholder(url: store.selectedSpace.flatMap { SidebarDrag.current?.url(in: $0) }, cornerRadius: 12)
                            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                    }
                }
            }
        }
        .frame(minHeight: favorites.isEmpty ? Self.tileHeight : nil, alignment: .top)
        .overlay {
            if favorites.isEmpty && placeholder == nil {
                Text("Drag a tab here to pin it").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onDrop(of: [.utf8PlainText], delegate: DropHandler(grid: self))
        .animation(.dropReflow, value: slots.map(\.id))
    }

    private func tile(_ favorite: Favorite) -> some View {
        Button { store.openFavorite(favorite) } label: {
            FaviconView(url: favorite.url, size: 22)
                .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .help(favorite.title)
        .onDrag { SidebarDrag.favorite(favorite.id).itemProvider(pool: pool) }
        .contextMenu {
            Button("Remove from Favorites", role: .destructive) { store.removeFavorite(favorite.id) }
        }
    }

    /// The insertion point nearest the pointer: between tiles, row by row.
    private func dropIndex(at point: CGPoint) -> Int {
        let tileWidth = (width - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        let column = Int(((point.x + Self.spacing / 2) / (tileWidth + Self.spacing)).rounded())
        let row = Int(max(point.y, 0) / (Self.tileHeight + Self.spacing))
        return min(row * Self.columns + min(max(column, 0), Self.columns), staying.count)
    }

    private struct DropHandler: DropDelegate {
        let grid: FavoritesGrid

        func validateDrop(info: DropInfo) -> Bool { SidebarDrag.current?.canSplit == true }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            let index = grid.dropIndex(at: info.location)
            if grid.placeholder != index { withAnimation(.dropReflow) { grid.placeholder = index } }
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            withAnimation(.dropReflow) { grid.placeholder = nil }
        }

        func performDrop(info: DropInfo) -> Bool {
            let index = grid.placeholder ?? grid.staying.count
            let favorites = grid.favorites, store = grid.store, placeholder = grid.$placeholder
            return SidebarDrag.load(from: info) { drag in
                // The placeholder turns into the real tile in the same animation, so nothing jumps.
                withAnimation(.dropReflow) {
                    placeholder.wrappedValue = nil
                    switch drag {
                    case .tab(let id): store.pinTab(id, at: index)
                    case .favorite(let id):
                        let from = favorites.firstIndex { $0.id == id } ?? index
                        store.moveFavorite(id, before: index >= from ? index + 1 : index)
                    case .split, nil: break
                    }
                }
                SidebarDrag.current = nil
            }
        }
    }
}

/// Open tabs, with each split as one row. Dragging a tab, favorite or split over the list
/// opens a row-height gap at the drop spot. ⌘- or ⇧-click marks several tabs, to open them
/// in split view from the context menu.
private struct TabList: View {
    let space: Space
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Namespace private var selection
    /// The gap's index among the rows, while a drag hovers the list.
    @State private var gap: Int?
    /// Tabs marked with ⌘- or ⇧-click.
    @State private var marked: [BrowserTab.ID] = []

    private static let headerHeight: CGFloat = 34
    private static let rowHeight: CGFloat = 36
    private static let spacing: CGFloat = 2

    private enum Row: Identifiable {
        case tab(BrowserTab), split(Split, [BrowserTab]), gap
        var id: String {
            switch self {
            case .tab(let tab): tab.id.uuidString
            case .split(let split, _): split.id.uuidString
            case .gap: "gap"
            }
        }
        var firstTabID: BrowserTab.ID? {
            switch self {
            case .tab(let tab): tab.id
            case .split(_, let tabs): tabs.first?.id
            case .gap: nil
            }
        }
    }

    /// Rows other than the one being dragged, which gives up its place to the gap. A split
    /// shows once, where its first tab is.
    private var staying: [Row] {
        let dragged = gap == nil ? nil : SidebarDrag.current
        var rows: [Row] = []
        var shown = Set<Split.ID>()
        for tab in space.tabs where dragged != .tab(tab.id) {
            if let split = space.splits?.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard dragged != .split(split.id), shown.insert(split.id).inserted else { continue }
                rows.append(.split(split, split.tabIDs.compactMap { id in space.tabs.first { $0.id == id } }))
            } else {
                rows.append(.tab(tab))
            }
        }
        return rows
    }

    private var rows: [Row] {
        var rows = staying
        if let gap { rows.insert(.gap, at: min(gap, rows.count)) }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.spacing) {
                Button { store.isCommandBarOpen = true } label: {
                    Label("New Tab", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    switch row {
                    case .tab(let tab):
                        TabRow(tab: tab, isSelected: tab.id == space.selectedTabID, isMarked: marked.contains(tab.id),
                               splitCandidates: marked.count >= 2 && marked.contains(tab.id) ? marked : [],
                               namespace: selection, onSelect: { select(tab.id) }, onSplit: { marked = [] })
                            .onDrag { SidebarDrag.tab(tab.id).itemProvider(pool: pool) }
                    case .split(let split, let tabs):
                        SplitRow(split: split, tabs: tabs, isSelected: split.tabIDs.contains(space.selectedTabID ?? UUID()),
                                 namespace: selection)
                            .onDrag { SidebarDrag.split(split.id).itemProvider(pool: pool) }
                    case .gap:
                        DropPlaceholder(url: SidebarDrag.current?.url(in: space), cornerRadius: 10)
                            .frame(height: Self.rowHeight)
                    }
                }
            }
            .font(.system(size: 13))
            // Room below the last tab to drop at the end of the list.
            .padding(.bottom, 40)
            .contentShape(.rect)
            .onDrop(of: [.utf8PlainText], delegate: DropHandler(list: self))
        }
        .scrollIndicators(.never)
        .animation(.dropReflow, value: rows.map(\.id))
        .onChange(of: space.id) { marked = [] }
    }

    /// A plain click selects; ⌘-click toggles a mark and ⇧-click marks a range, starting
    /// from the selected tab.
    private func select(_ id: BrowserTab.ID) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let order = staying.compactMap { row -> BrowserTab.ID? in if case .tab(let tab) = row { tab.id } else { nil } }
        if flags.contains(.command) {
            if marked.isEmpty, let current = space.selectedTabID, current != id, order.contains(current) { marked = [current] }
            if let i = marked.firstIndex(of: id) { marked.remove(at: i) } else { marked.append(id) }
        } else if flags.contains(.shift), let anchor = marked.last ?? space.selectedTabID,
                  let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
            marked = Array(order[min(a, b)...max(a, b)])
        } else {
            marked = []
            store.selectTab(id)
        }
    }

    /// The insertion point nearest the pointer, between rows.
    private func dropIndex(at point: CGPoint) -> Int {
        let y = point.y - Self.headerHeight - Self.spacing
        let index = Int((y / (Self.rowHeight + Self.spacing)).rounded())
        return min(max(index, 0), staying.count)
    }

    private struct DropHandler: DropDelegate {
        let list: TabList

        func validateDrop(info: DropInfo) -> Bool { SidebarDrag.current != nil }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            let index = list.dropIndex(at: info.location)
            if list.gap != index { withAnimation(.dropReflow) { list.gap = index } }
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            withAnimation(.dropReflow) { list.gap = nil }
        }

        func performDrop(info: DropInfo) -> Bool {
            let rows = list.staying, row = list.gap ?? rows.count
            let tabs = list.space.tabs, store = list.store, gap = list.$gap
            // The gap sits before a row; the store wants the index of that row's first tab.
            let index = rows.indices.contains(row) ? rows[row].firstTabID.flatMap { id in tabs.firstIndex { $0.id == id } } : nil
            return SidebarDrag.load(from: info) { drag in
                withAnimation(.dropReflow) {
                    gap.wrappedValue = nil
                    switch drag {
                    case .tab(let id): store.moveTabs([id], before: index)
                    case .split(let id):
                        if let split = store.selectedSpace?.splits?.first(where: { $0.id == id }) {
                            store.moveTabs(split.tabIDs, before: index)
                        }
                    case .favorite(let id): store.unpinFavorite(id, toTabAt: index)
                    case nil: break
                    }
                }
                SidebarDrag.current = nil
            }
        }
    }
}

private struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isMarked: Bool
    /// The marked tabs, when this one is among two or more of them.
    let splitCandidates: [BrowserTab.ID]
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onSplit: () -> Void
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(url: tab.url, size: 16)
            Text(tab.title).lineLimit(1).fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 0)
            if hovering {
                Button { pool.close(tab.id); store.closeTab(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.tint(.white.opacity(0.4)), in: .rect(cornerRadius: 10))
                    .glassEffectID("selected-tab", in: namespace)
            } else if isMarked {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.14))
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            if splitCandidates.count >= 2 {
                Button("Open \(min(splitCandidates.count, Split.maxPanes)) Tabs in Split View") {
                    store.makeSplit(splitCandidates)
                    onSplit()
                }
            } else if let current = store.selectedTab?.id, current != tab.id {
                Button("Add to Split View") { store.addToSplit(tab.id, beside: current) }
            }
            Button("Add to Favorites") { store.addFavorite(from: tab) }
            Divider()
            Button("Close Tab") { pool.close(tab.id); store.closeTab(tab.id) }
        }
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}

/// A split as one row: each pane's favicon and title side by side, split by thin lines.
private struct SplitRow: View {
    let split: Split
    let tabs: [BrowserTab]
    let isSelected: Bool
    let namespace: Namespace.ID
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    Rectangle().fill(.primary.opacity(0.2)).frame(width: 1, height: 18)
                }
                HStack(spacing: 6) {
                    FaviconView(url: tab.url, size: 14)
                    Text(tab.title).lineLimit(1).fontWeight(isSelected ? .semibold : .regular)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 36)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.tint(.white.opacity(0.4)), in: .rect(cornerRadius: 10))
                    .glassEffectID("selected-tab", in: namespace)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            // Show the split, focused on the pane used last.
            if !isSelected, let pane = tabs.max(by: { $0.lastActive < $1.lastActive }) { store.selectTab(pane.id) }
        }
        .contextMenu {
            Button("Separate Tabs") { store.dissolveSplit(split.id) }
            Divider()
            Button("Close Split") {
                for tab in tabs { pool.close(tab.id); store.closeTab(tab.id) }
            }
        }
        .help(tabs.map(\.title).joined(separator: " · "))
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}

/// Library on the left, one glyph per space in the middle, and the + menu on the right.
private struct BottomBar: View {
    @Environment(BrowserStore.self) private var store
    @State private var showsLibrary = false
    @State private var showsNewMenu = false

    var body: some View {
        HStack(spacing: 0) {
            Button { showsLibrary = true } label: { Image(systemName: "archivebox") }
                .help("Library")
                .popover(isPresented: $showsLibrary, arrowEdge: .top) { LibraryPopover(isPresented: $showsLibrary) }
            Spacer(minLength: 8)
            HStack(spacing: 16) {
                ForEach(store.spaces) { space in
                    SpaceGlyph(space: space, isActive: space.id == store.selectedSpaceID)
                }
            }
            Spacer(minLength: 8)
            Button { showsNewMenu = true } label: { Image(systemName: "plus").font(.system(size: 16)) }
                .help("New")
                .popover(isPresented: $showsNewMenu, arrowEdge: .top) { NewMenu(isPresented: $showsNewMenu) }
        }
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: 38)
        // Line the outer glyphs up with the side margins.
        .padding(.horizontal, -5)
    }
}

/// A space as a plain glyph: its symbol, or its first letter. The active one is tinted.
private struct SpaceGlyph: View {
    let space: Space
    let isActive: Bool
    @Environment(BrowserStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button { store.selectSpace(space.id) } label: {
            Group {
                if let icon = space.icon {
                    Image(systemName: icon)
                } else {
                    Text(space.name.prefix(1).uppercased()).fontWeight(.bold)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(isActive ? AnyShapeStyle(space.tint.color) : AnyShapeStyle(.primary.opacity(hovering ? 0.7 : 0.35)))
            .frame(width: 22, height: 24)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(space.name)
        .contextMenu {
            Menu("Icon") {
                Button("First Letter") { store.setIcon(nil, for: space.id) }
                Divider()
                ForEach(SpaceIcon.choices, id: \.self) { symbol in
                    Button { store.setIcon(symbol, for: space.id) } label: { Image(systemName: symbol) }
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}

/// Recently closed tabs of the current space; clicking one reopens it.
private struct LibraryPopover: View {
    @Binding var isPresented: Bool
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let closed = (store.selectedSpace?.recentlyClosed ?? []).reversed()
        VStack(alignment: .leading, spacing: 2) {
            Text("Recently Closed").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            if closed.isEmpty {
                Text("No recently closed tabs").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(Array(closed)) { tab in
                MenuRow(icon: nil, favicon: tab.url, title: tab.title) {
                    store.reopenClosedTab(tab.id)
                    isPresented = false
                }
            }
        }
        .padding(8)
        .frame(width: 260)
    }
}

/// The + menu: what you can create.
private struct NewMenu: View {
    @Binding var isPresented: Bool
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(icon: "plus.square.on.square", title: "New Space") { run { store.isCreatingSpace = true } }
            MenuRow(icon: "folder.badge.plus", title: "New Folder") {}.disabled(true)
            Divider().padding(.vertical, 3)
            MenuRow(icon: "scribble.variable", title: "New Easel") {}.disabled(true)
            MenuRow(icon: "paintbrush.pointed", title: "New Boost") {}.disabled(true)
            Divider().padding(.vertical, 3)
            MenuRow(icon: "rectangle.split.2x1", title: "New Split", shortcut: "⌃⇧=") { run { store.startNewSplit() } }
            MenuRow(icon: "plus", title: "New Tab", shortcut: "⌘T") { run { store.isCommandBarOpen = true } }
        }
        .padding(6)
        .frame(width: 230)
    }

    private func run(_ action: () -> Void) {
        isPresented = false
        action()
    }
}

/// One row of a sidebar popover menu, highlighted on hover like a native menu item.
private struct MenuRow: View {
    let icon: String?
    var favicon: URL? = nil
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let favicon {
                    FaviconView(url: favicon, size: 16)
                } else if let icon {
                    Image(systemName: icon).frame(width: 18)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(isEnabled ? 1 : 0.35)))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Color.accentColor : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var highlighted: Bool { hovering && isEnabled }
}

/// Replaces the sidebar's content while making a space: name and icon, profile, theme.
private struct CreateSpaceForm: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var icon: String?
    /// nil makes a new profile; otherwise the space shares that profile's logins.
    @State private var profileID: Profile.ID?
    @State private var showsIcons = false
    @State private var showsProfileInfo = false
    @State private var showsThemes = false
    @FocusState private var nameFocused: Bool

    private var tint: SpaceTint { store.draftTint ?? .teal }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var fieldFill: Color { colorScheme == .dark ? .white.opacity(0.11) : .black.opacity(0.05) }

    var body: some View {
        VStack(spacing: 14) {
            Illustration(tint: tint).padding(.top, 18)
            VStack(spacing: 5) {
                Text("Create a Space").font(.system(size: 20, weight: .semibold))
                Text("Separate your tabs for life, work, projects, and more.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Button { showsIcons = true } label: {
                    Group {
                        if let icon { Image(systemName: icon).foregroundStyle(tint.color) } else { Image(systemName: "plus") }
                    }
                    .font(.system(size: 13))
                    .frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: icon == nil ? [3, 2] : [])))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .popover(isPresented: $showsIcons, arrowEdge: .bottom) { iconGrid }
                TextField("Space name…", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($nameFocused)
                    .onSubmit(create)
            }
            .padding(.horizontal, 6)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(fieldFill))

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                Text("Profile")
                Spacer(minLength: 4)
                Picker("Profile", selection: $profileID) {
                    Text("New Profile").tag(Profile.ID?.none)
                    Divider()
                    ForEach(store.profiles) { profile in Text(profile.name).tag(Profile.ID?.some(profile.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Button { showsProfileInfo = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .popover(isPresented: $showsProfileInfo, arrowEdge: .bottom) {
                        Text("A space's profile keeps its own logins, cookies and history. Spaces that share a profile share logins.")
                            .font(.system(size: 12))
                            .frame(width: 220)
                            .padding(12)
                    }
            }
            .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.snappy(duration: 0.2)) { showsThemes.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush").foregroundStyle(.secondary)
                        Text("Choose a Theme")
                        Spacer()
                        Circle().fill(tint.color).frame(width: 12, height: 12)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsThemes ? 180 : 0))
                    }
                    .font(.system(size: 13))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if showsThemes {
                    HStack(spacing: 10) {
                        ForEach(SpaceTint.allCases, id: \.self) { choice in
                            Button { withAnimation(.snappy(duration: 0.2)) { store.draftTint = choice } } label: {
                                Circle().fill(choice.color).frame(width: 22, height: 22)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(choice == tint ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(choice.rawValue.capitalized)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: create) {
                    Text("Create Space")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(trimmedName.isEmpty ? 0.45 : 1)
                .disabled(trimmedName.isEmpty)
                .keyboardShortcut(.defaultAction)
                Button("Cancel", action: close)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            if store.draftTint == nil {
                let used = Set(store.spaces.map(\.tint))
                store.draftTint = SpaceTint.allCases.first { !used.contains($0) } ?? .teal
            }
            nameFocused = true
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 6), spacing: 4) {
            IconChoice(symbol: nil, label: String(trimmedName.prefix(1)).uppercased(), selection: $icon, tint: tint)
            ForEach(SpaceIcon.choices, id: \.self) { symbol in
                IconChoice(symbol: symbol, label: nil, selection: $icon, tint: tint)
            }
        }
        .padding(10)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        store.addSpace(name: trimmedName, tint: tint, icon: icon, profileID: profileID)
        close()
    }

    private func close() {
        store.draftTint = nil
        store.isCreatingSpace = false
    }

    /// Three slightly fanned cards, as in Arc's space creation.
    private struct Illustration: View {
        let tint: SpaceTint

        var body: some View {
            ZStack {
                card("leaf.fill", angle: -12, x: -34)
                card("books.vertical.fill", angle: 12, x: 34)
                card("laptopcomputer", angle: 0, x: 0)
            }
            .frame(height: 70)
        }

        private func card(_ symbol: String, angle: Double, x: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .frame(width: 50, height: 60)
                .overlay(Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(tint.color))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .rotationEffect(.degrees(angle))
                .offset(x: x, y: angle == 0 ? -4 : 2)
        }
    }
}

private struct IconChoice: View {
    let symbol: String?
    let label: String?
    @Binding var selection: String?
    let tint: SpaceTint

    var body: some View {
        let selected = selection == symbol
        Button { selection = symbol } label: {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(label?.isEmpty == false ? label! : "A").fontWeight(.bold) }
            }
            .font(.system(size: 12))
            .foregroundStyle(selected ? .white : .secondary)
            .frame(width: 26, height: 26)
            .background(selected ? AnyShapeStyle(tint.color) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(symbol ?? "First letter of the name")
    }
}

struct FaviconView: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url.faviconURL) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            RoundedRectangle(cornerRadius: size * 0.25).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.25))
    }
}
