import SwiftUI

struct Sidebar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var swipe = SpaceSwipeTracker()
    @State private var width: CGFloat = 264

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationRow()
            Group {
                if store.isCreatingSpace {
                    CreateSpaceForm()
                } else if let space = store.selectedSpace {
                    swipeableContent(space)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            swipe.frame = frame
            width = frame.width
        }
        .onAppear {
            swipe.store = store
            swipe.start()
        }
        .onDisappear { swipe.stop() }
    }

    /// The space's content, and during a swipe the neighbor's beside it, both following the
    /// fingers. The neighbor is only built while a swipe shows it.
    private func swipeableContent(_ space: Space) -> some View {
        let progress = store.swipeProgress
        let neighbor = store.neighborSpace(towardProgress: progress)
        return ZStack(alignment: .topLeading) {
            SpaceContent(space: space)
                .offset(x: progress * width)
            if let neighbor {
                SpaceContent(space: neighbor)
                    .offset(x: (progress > 0 ? progress - 1 : progress + 1) * width)
                    .id(neighbor.id)
            }
        }
        // Clip at the sidebar's edges, not at its margins.
        .padding(.horizontal, Self.margin)
        .clipped()
        .padding(.horizontal, -Self.margin)
    }

    static let margin: CGFloat = 10
}

/// One space's address bar, favorites and tabs.
private struct SpaceContent: View {
    let space: Space
    @Environment(BrowserStore.self) private var store
    @AppStorage(PreferenceKey.showsAddressPill) private var showsAddressPill = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsAddressPill {
                AddressPill(tab: space.pageTab(space.selectedTabID), profile: store.profile(for: space))
            }
            FavoritesGrid(favorites: space.favorites)
            Divider().padding(.horizontal, 8)
            TabList(space: space)
        }
        .padding(.top, 5)
    }
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
    @AppStorage(PreferenceKey.sidebarSide) private var sidebarSide = SidebarSide.left

    var body: some View {
        let page = pool.existingPage(for: store.selectedTab?.id)
        let _ = pool.revision
        // Shares the title bar row with the traffic lights, on their center line (15.5pt).
        HStack(spacing: 10) {
            Button { withAnimation(.sidebar) { store.isSidebarVisible.toggle() } } label: {
                Image(systemName: sidebarSide == .left ? "sidebar.left" : "sidebar.right")
            }
            .help(store.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            Spacer()
            Button { page?.goBack() } label: { Image(systemName: "arrow.left") }
                .disabled(!(page?.canGoBack ?? false))
            Button { page?.goForward() } label: { Image(systemName: "arrow.right") }
                .disabled(!(page?.canGoForward ?? false))
            if let id = store.selectedTab?.id, pool.loadingProgress[id] != nil {
                Button { page?.stopLoading() } label: { Image(systemName: "xmark") }
                    .help("Stop")
            } else {
                Button { page?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(page == nil)
                    .help("Reload")
            }
        }
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: 31)
        // The toggle's glyph starts ~12pt after the last traffic light (which ends at ~67pt);
        // reload's glyph ends on the URL pill's right edge. On the right, there are no lights.
        .padding(.leading, sidebarSide == .left ? 64 : -5)
        .padding(.trailing, -5)
    }
}

/// The current page's address, flat like Arc's: host only, with copy, extensions and page actions.
private struct AddressPill: View {
    /// The space's selected tab.
    let tab: BrowserTab?
    /// The space's profile, whose extensions the puzzle button shows.
    let profile: Profile?
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.colorScheme) private var colorScheme
    @State private var justCopied = false
    @State private var showsPageInfo = false
    @State private var showsSiteSettings = false

    var body: some View {
        let url = tab?.url
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
            }
            if let profile, pool.supportsExtensions {
                ExtensionsButton(profile: profile)
            }
            if url != nil {
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
    case folder(Folder.ID)

    /// The drag in progress, so drop targets can show its placeholder while hovering. Drops
    /// themselves trust only the dragged string, since this can be stale after a cancelled drag.
    @MainActor static var current: SidebarDrag?

    var token: String {
        switch self {
        case .tab(let id): "embark-tab:\(id.uuidString)"
        case .favorite(let id): "embark-favorite:\(id.uuidString)"
        case .split(let id): "embark-split:\(id.uuidString)"
        case .folder(let id): "embark-folder:\(id.uuidString)"
        }
    }

    /// Tabs and favorites can become split panes or favorites; splits and folders can't.
    var canSplit: Bool {
        switch self {
        case .tab, .favorite: true
        case .split, .folder: false
        }
    }

    init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "embark-tab": self = .tab(id)
        case "embark-favorite": self = .favorite(id)
        case "embark-split": self = .split(id)
        case "embark-folder": self = .folder(id)
        default: return nil
        }
    }

    @MainActor func url(in space: Space) -> URL? {
        switch self {
        case .tab(let id): space.tabs.first { $0.id == id }?.url
        case .favorite(let id): space.favorites.first { $0.id == id }?.url
        case .split(let id):
            space.splits?.first { $0.id == id }.flatMap { split in space.tabs.first { $0.id == split.tabIDs.first }?.url }
        case .folder: nil
        }
    }

    /// Starts dragging this item; used with `.onDrag`. Pages stop taking drops until the drag
    /// ends, so it can land on the page area to make a split.
    @MainActor func itemProvider(pool: PagePool) -> NSItemProvider {
        Self.current = self
        // Starting resets anything left over from an earlier drag.
        pool.store?.dragSession.begin(token)
        pool.suspendPageDrops()
        // A folder name being edited would take the drag's text if it landed there.
        pool.store?.renamingFolderID = nil
        Self.watchForEnd(store: pool.store)
        return NSItemProvider(object: token as NSString)
    }

    /// Ends the drag: no more placeholders or highlights anywhere.
    @MainActor static func finish(store: BrowserStore?) {
        current = nil
        store?.dragSession.finish()
    }

    /// Clears the drag once the mouse is released, however the drag ended: dropped in the
    /// sidebar, elsewhere, or cancelled. Drop targets clear leftover placeholders on this.
    @MainActor private static func watchForEnd(store: BrowserStore?) {
        Task {
            while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            // Let a drop's own handling finish first.
            try? await Task.sleep(for: .milliseconds(300))
            finish(store: store)
        }
    }

    /// Removes drag tokens from text, in case one landed in a text field.
    static func strippingTokens(_ text: String) -> String {
        Folder.strippingDragTokens(text)
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
        if let placeholder, store.activeDrag != nil { slots.insert(.placeholder, at: min(placeholder, slots.count)) }
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
        .onChange(of: store.dragSession.changes) { withAnimation(.dropReflow) { placeholder = nil } }
        .animation(.dropReflow, value: slots.map(\.id))
    }

    private func tile(_ favorite: Favorite) -> some View {
        // A favorite is its own tab: selecting it shows its own page and highlights the tile.
        let isSelected = favorite.tab.map { $0.id == store.selectedSpace?.selectedTabID } ?? false
        return Button { store.selectFavorite(favorite.id) } label: {
            FaviconView(url: favorite.url, size: 22)
                .opacity(favorite.tab?.isUnloaded == true ? 0.5 : 1)
                .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.white.opacity(0.45)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 12))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .help(favorite.tab?.title ?? favorite.title)
        .onDrag { SidebarDrag.favorite(favorite.id).itemProvider(pool: pool) }
        .contextMenu {
            Button("Remove from Favorites", role: .destructive) {
                if let page = store.removeFavorite(favorite.id) { pool.close(page) }
            }
        }
        .animation(.smooth(duration: 0.2), value: isSelected)
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
            let loading = SidebarDrag.load(from: info) { drag in
                // The placeholder turns into the real tile in the same animation, so nothing jumps.
                withAnimation(.dropReflow) {
                    placeholder.wrappedValue = nil
                    switch drag {
                    case .tab(let id): store.pinTab(id, at: index)
                    case .favorite(let id):
                        let from = favorites.firstIndex { $0.id == id } ?? index
                        store.moveFavorite(id, before: index >= from ? index + 1 : index)
                    case .split, .folder, nil: break
                    }
                }
                SidebarDrag.finish(store: store)
            }
            if !loading { SidebarDrag.finish(store: store) }
            return loading
        }
    }
}

/// The space's folders, then its loose tabs, with each split as one row. Folders nest and
/// collapse like Arc's; a collapsed folder still shows the selected tab if it's inside.
/// Dragging a tab, favorite, split or folder over the list opens a row-height gap at the drop
/// spot, indented to the folder it would land in, and hovering a collapsed folder springs it
/// open. ⌘- or ⇧-click marks several tabs for the context menu.
private struct TabList: View {
    let space: Space
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Namespace private var selection
    /// The gap's index among the rows, while a drag hovers the list.
    @State private var gap: Int?
    /// Tabs marked with ⌘- or ⇧-click.
    @State private var marked: [BrowserTab.ID] = []
    /// The collapsed folder a drag is hovering, and when it started, to spring it open.
    @State private var springFolder: Folder.ID?
    /// The folder row a drag is over: dropping there puts the item into that folder, last.
    @State private var dropFolder: Folder.ID?

    private static let headerHeight: CGFloat = 34
    private static let rowHeight: CGFloat = 36
    private static let spacing: CGFloat = 2
    /// How far each folder level is indented. The guide line sits under the parent folder's
    /// icon with about 8pt of room before the child rows.
    static let indent: CGFloat = 26

    private enum Row: Identifiable {
        case folder(Folder, depth: Int)
        case tab(BrowserTab, depth: Int, container: Folder.ID?)
        case split(Split, [BrowserTab], depth: Int, container: Folder.ID?)
        case gap(depth: Int)

        var id: String {
            switch self {
            case .folder(let folder, _): folder.id.uuidString
            case .tab(let tab, _, _): tab.id.uuidString
            case .split(let split, _, _, _): split.id.uuidString
            case .gap: "gap"
            }
        }

        var depth: Int {
            switch self {
            case .folder(_, let depth), .tab(_, let depth, _), .split(_, _, let depth, _), .gap(let depth): depth
            }
        }

        /// The folder the row sits in.
        var container: Folder.ID? {
            switch self {
            case .folder(let folder, _): folder.parentID
            case .tab(_, _, let container), .split(_, _, _, let container): container
            case .gap: nil
            }
        }

        var firstTabID: BrowserTab.ID? {
            switch self {
            case .tab(let tab, _, _): tab.id
            case .split(_, let tabs, _, _): tabs.first?.id
            default: nil
            }
        }
    }

    /// Rows other than the one being dragged, which gives up its place to the gap.
    private var staying: [Row] {
        let dragged = gap == nil ? nil : SidebarDrag.current
        var rows: [Row] = []
        var shownSplits = Set<Split.ID>()
        let selectedID = space.selectedTabID

        func appendTabs(in container: Folder.ID?, depth: Int, only: BrowserTab.ID? = nil) {
            for tab in space.tabs where tab.folderID == container && dragged != .tab(tab.id) {
                if let only, tab.id != only, space.splits?.first(where: { $0.tabIDs.contains(only) })?.tabIDs.contains(tab.id) != true { continue }
                if let split = space.splits?.first(where: { $0.tabIDs.contains(tab.id) }) {
                    guard dragged != .split(split.id), shownSplits.insert(split.id).inserted else { continue }
                    rows.append(.split(split, split.tabIDs.compactMap { id in space.tabs.first { $0.id == id } },
                                       depth: depth, container: container))
                } else {
                    rows.append(.tab(tab, depth: depth, container: container))
                }
            }
        }

        func appendFolder(_ folder: Folder, depth: Int) {
            guard dragged != .folder(folder.id) else { return }
            rows.append(.folder(folder, depth: depth))
            if folder.isExpanded {
                for sub in space.subfolders(of: folder.id) { appendFolder(sub, depth: depth + 1) }
                appendTabs(in: folder.id, depth: depth + 1)
            } else if let selectedID, let tab = space.tabs.first(where: { $0.id == selectedID }),
                      let folderID = tab.folderID, space.folderAndDescendants(folder.id).contains(folderID) {
                // Arc keeps the selected tab visible under its collapsed folder.
                appendTabs(in: folderID, depth: depth + 1, only: selectedID)
            }
        }

        for folder in space.subfolders(of: nil) { appendFolder(folder, depth: 0) }
        appendTabs(in: nil, depth: 0)
        return rows
    }

    private var rows: [Row] {
        var rows = staying
        if let gap, store.activeDrag != nil {
            let index = min(gap, rows.count)
            rows.insert(.gap(depth: dropTarget(at: index, in: rows).depth), at: index)
        }
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
                    rowView(row).modifier(Indented(depth: row.depth))
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
        .onChange(of: store.dragSession.changes) {
            withAnimation(.dropReflow) {
                gap = nil
                dropFolder = nil
                springFolder = nil
            }
        }
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .folder(let folder, let depth):
            FolderRow(folder: folder, depth: depth, space: space, isSpringTarget: springFolder == folder.id,
                      isDropTarget: dropFolder == folder.id && store.activeDrag != nil)
                .onDrag { SidebarDrag.folder(folder.id).itemProvider(pool: pool) }
        case .tab(let tab, _, _):
            TabRow(tab: tab, isSelected: tab.id == space.selectedTabID, isMarked: marked.contains(tab.id),
                   markedTabs: marked.count >= 2 && marked.contains(tab.id) ? marked : [],
                   namespace: selection, onSelect: { select(tab.id) }, onMarkedUsed: { marked = [] })
                .onDrag { SidebarDrag.tab(tab.id).itemProvider(pool: pool) }
        case .split(let split, let tabs, _, _):
            SplitRow(split: split, tabs: tabs, isSelected: split.tabIDs.contains(space.selectedTabID ?? UUID()),
                     namespace: selection)
                .onDrag { SidebarDrag.split(split.id).itemProvider(pool: pool) }
        case .gap:
            DropPlaceholder(url: SidebarDrag.current?.url(in: space), cornerRadius: 10)
                .frame(height: Self.rowHeight)
        }
    }

    /// A plain click selects; ⌘-click toggles a mark and ⇧-click marks a range, starting
    /// from the selected tab.
    private func select(_ id: BrowserTab.ID) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let order = staying.compactMap { row -> BrowserTab.ID? in if case .tab(let tab, _, _) = row { tab.id } else { nil } }
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

    /// Where a drop before row `index` lands: right under an expanded folder's header it goes
    /// into that folder; otherwise into the folder of the row after it (the space's loose tabs
    /// at the end).
    private func dropTarget(at index: Int, in rows: [Row]) -> (folder: Folder.ID?, before: Row?, depth: Int) {
        if index > 0, case .folder(let folder, let depth) = rows[index - 1], folder.isExpanded {
            return (folder.id, rows.indices.contains(index) ? rows[index] : nil, depth + 1)
        }
        guard rows.indices.contains(index) else { return (nil, nil, 0) }
        let next = rows[index]
        return (next.container, next, next.depth)
    }

    /// The insertion point nearest the pointer, between rows.
    private func dropIndex(at point: CGPoint) -> Int {
        let y = point.y - Self.headerHeight - Self.spacing
        let index = Int((y / (Self.rowHeight + Self.spacing)).rounded())
        return min(max(index, 0), staying.count)
    }

    /// The folder whose row's middle half is under the pointer.
    private func folderUnderPointer(_ point: CGPoint) -> Folder? {
        let y = point.y - Self.headerHeight - Self.spacing
        let pitch = Self.rowHeight + Self.spacing
        let rows = staying
        let index = Int(floor(y / pitch))
        guard rows.indices.contains(index), case .folder(let folder, _) = rows[index] else { return nil }
        // Rows shift once a gap opens, so this is measured against the rows without one.
        let within = y - CGFloat(index) * pitch
        guard within > Self.rowHeight * 0.25, within < Self.rowHeight * 0.75 else { return nil }
        // A folder can't go into itself.
        if case .folder(let dragged) = SidebarDrag.current, space.folderAndDescendants(dragged).contains(folder.id) { return nil }
        return folder
    }

    /// The row under the pointer, for springing folders open.
    private func row(at point: CGPoint) -> Row? {
        let y = point.y - Self.headerHeight - Self.spacing
        let rows = rows
        let index = Int(floor(y / (Self.rowHeight + Self.spacing)))
        return rows.indices.contains(index) ? rows[index] : nil
    }

    private struct DropHandler: DropDelegate {
        let list: TabList

        func validateDrop(info: DropInfo) -> Bool { SidebarDrag.current != nil }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // Over the middle of a folder row, the drop goes into the folder: highlight it
            // instead of opening a gap.
            if let folder = list.folderUnderPointer(info.location) {
                if list.dropFolder != folder.id || list.gap != nil {
                    withAnimation(.dropReflow) {
                        list.dropFolder = folder.id
                        list.gap = nil
                    }
                }
                springOpen(.folder(folder, depth: 0))
                return DropProposal(operation: .move)
            }
            list.dropFolder = nil
            let index = list.dropIndex(at: info.location)
            if list.gap != index { withAnimation(.dropReflow) { list.gap = index } }
            springOpen(list.row(at: info.location))
            return DropProposal(operation: .move)
        }

        /// A collapsed folder hovered for half a second opens.
        private func springOpen(_ row: Row?) {
            guard case .folder(let folder, _) = row, !folder.isExpanded else { list.springFolder = nil; return }
            guard list.springFolder != folder.id else { return }
            list.springFolder = folder.id
            let store = list.store, spring = list.$springFolder
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Not once the drag is over (or it dropped meanwhile).
                guard spring.wrappedValue == folder.id, store.activeDrag != nil else { return }
                withAnimation(.dropReflow) { store.setFolderExpanded(folder.id, true) }
            }
        }

        func dropExited(info: DropInfo) {
            list.springFolder = nil
            withAnimation(.dropReflow) {
                list.gap = nil
                list.dropFolder = nil
            }
        }

        func performDrop(info: DropInfo) -> Bool {
            let rows = list.staying
            let intoFolder = list.dropFolder
            var target = list.dropTarget(at: list.gap ?? rows.count, in: rows)
            if let intoFolder { target = (intoFolder, nil, 0) }
            list.dropFolder = nil
            let space = list.space, store = list.store, gap = list.$gap
            // The target is worked out; clear the gap and highlights now rather than after the
            // payload loads, so nothing can stay behind.
            list.springFolder = nil
            list.gap = nil
            // Tabs go before the row's first tab, or first among the folder's tabs when the
            // row is a subfolder (subfolders come before tabs).
            // Dropped on a folder row: last in that folder.
            let anchorTab: BrowserTab.ID? = intoFolder != nil ? nil : target.before?.firstTabID
                ?? (target.before == nil ? nil : space.tabs(in: target.folder).first?.id)
            let anchorFolder: Folder.ID? = if case .folder(let folder, _) = target.before { folder.id } else { nil }
            let loading = SidebarDrag.load(from: info) { drag in
                withAnimation(.dropReflow) {
                    gap.wrappedValue = nil
                    switch drag {
                    case .tab(let id): store.moveTabs([id], toFolder: target.folder, before: anchorTab)
                    case .split(let id):
                        if let split = space.splits?.first(where: { $0.id == id }) {
                            store.moveTabs(split.tabIDs, toFolder: target.folder, before: anchorTab)
                        }
                    case .folder(let id): store.moveFolder(id, to: target.folder, before: anchorFolder)
                    case .favorite(let id):
                        store.unpinFavorite(id, toFolder: target.folder, before: anchorTab)
                    case nil: break
                    }
                }
                SidebarDrag.finish(store: store)
            }
            if !loading { SidebarDrag.finish(store: store) }
            return loading
        }
    }
}

/// Indents a tab-list row by its folder depth, with a thin guide line per level.
private struct Indented: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        content
            .padding(.leading, CGFloat(depth) * TabList.indent)
            .overlay(alignment: .leading) {
                if depth > 0 {
                    ForEach(0..<depth, id: \.self) { level in
                        Rectangle()
                            .fill(.primary.opacity(0.10))
                            .frame(width: 1)
                            .padding(.vertical, -1)
                            .offset(x: CGFloat(level) * TabList.indent + 18)
                    }
                }
            }
    }
}

/// A folder header: open or closed folder, its name (renamed in place), and a chevron on hover.
private struct FolderRow: View {
    let folder: Folder
    let depth: Int
    let space: Space
    var isSpringTarget = false
    /// A drag over the row would drop into this folder.
    var isDropTarget = false
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var hovering = false
    @State private var draftName = ""
    @State private var confirmsDelete = false
    @FocusState private var nameFocused: Bool

    private var isRenaming: Bool { store.renamingFolderID == folder.id }
    private var tabCount: Int { space.tabIDs(under: folder.id).count }

    var body: some View {
        HStack(spacing: 10) {
            FolderGlyph(isOpen: folder.isExpanded)
                .foregroundStyle(.secondary)
                // Dimmed while a drag hovering it is about to spring it open.
                .opacity(isSpringTarget ? 0.45 : 1)
            if isRenaming {
                TextField("Folder name", text: $draftName)
                    // Never keep a drag's payload if one is dropped into the field.
                    .onChange(of: draftName) {
                        let clean = SidebarDrag.strippingTokens(draftName)
                        if clean != draftName { draftName = clean }
                    }
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { store.renamingFolderID = nil }
                    .onAppear { draftName = folder.name }
                    // After a beat, so a closing popover (the + menu) has given the window back
                    // keyboard focus.
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        nameFocused = true
                    }
            } else {
                Text(folder.name).lineLimit(1)
                    .onTapGesture(count: 2) { store.renamingFolderID = folder.id }
            }
            Spacer(minLength: 0)
            if hovering && !isRenaming {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.06 : 0))
            }
        }
        .contentShape(.rect)
        .onTapGesture { if !isRenaming { toggle() } }
        .onHover { hovering = $0 }
        .focusable(!isRenaming)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { setExpanded(false); return .handled }
        .onKeyPress(.rightArrow) { setExpanded(true); return .handled }
        .contextMenu {
            Button("Rename") { store.renamingFolderID = folder.id }
            Button("New Subfolder") { store.addFolder(in: folder.id) }
                .disabled(depth + 1 >= Folder.maxDepth)
            Divider()
            Button("Expand All") { withAnimation(.folderToggle) { store.setFoldersExpanded(true, under: folder.id) } }
            Button("Collapse All") { withAnimation(.folderToggle) { store.setFoldersExpanded(false, under: folder.id) } }
            Divider()
            Button("Close All Tabs") {
                for id in store.unloadFolder(folder.id) { pool.close(id) }
            }
            .disabled(tabCount == 0)
            Button("Delete Folder…", role: .destructive) {
                if tabCount == 0 { store.deleteFolder(folder.id, closingTabs: false) } else { confirmsDelete = true }
            }
        }
        .confirmationDialog("Delete “\(folder.name)”?", isPresented: $confirmsDelete) {
            Button("Close \(tabCount == 1 ? "1 Tab" : "\(tabCount) Tabs")", role: .destructive) {
                for id in store.deleteFolder(folder.id, closingTabs: true) { pool.close(id) }
            }
            Button("Keep Tabs") { store.deleteFolder(folder.id, closingTabs: false) }
        } message: {
            Text("Its tabs can be closed, or kept by moving them out of the folder.")
        }
        .help(folder.name)
    }

    private func toggle() { setExpanded(!folder.isExpanded) }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.folderToggle) { store.setFolderExpanded(folder.id, expanded) }
    }

    private func commitRename() {
        store.renameFolder(folder.id, to: SidebarDrag.strippingTokens(draftName))
        store.renamingFolderID = nil
    }
}

/// Arc's folder icons: a closed folder outline, and an open one with its front flap tilted
/// forward. SF Symbols has no open folder, so that one is drawn to match `folder`'s box,
/// baseline and stroke.
private struct FolderGlyph: View {
    let isOpen: Bool

    var body: some View {
        ZStack {
            Image(systemName: "folder")
                .font(.system(size: 15))
                .opacity(isOpen ? 0 : 1)
                .scaleEffect(isOpen ? 0.92 : 1)
            OpenFolderShape()
                .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .frame(width: 16.5, height: 13.4)
                .opacity(isOpen ? 1 : 0)
                .scaleEffect(isOpen ? 1 : 0.92)
        }
        .frame(width: 18, height: 16)
        .animation(.snappy(duration: 0.15), value: isOpen)
    }
}

/// An open folder: the back with its tab, and the front flap tipped forward.
private struct OpenFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        // Back panel with the tab, ending where the flap covers it.
        path.move(to: p(0.06, 0.93))
        path.addLine(to: p(0.06, 0.16))
        path.addQuadCurve(to: p(0.13, 0.06), control: p(0.06, 0.06))
        path.addLine(to: p(0.36, 0.06))
        path.addLine(to: p(0.45, 0.19))
        path.addLine(to: p(0.84, 0.19))
        path.addQuadCurve(to: p(0.90, 0.26), control: p(0.90, 0.19))
        path.addLine(to: p(0.90, 0.40))
        // Front flap, tipped forward.
        path.move(to: p(0.06, 0.93))
        path.addLine(to: p(0.22, 0.47))
        path.addQuadCurve(to: p(0.28, 0.40), control: p(0.235, 0.40))
        path.addLine(to: p(0.94, 0.40))
        path.addQuadCurve(to: p(0.985, 0.47), control: p(1.0, 0.40))
        path.addLine(to: p(0.85, 0.89))
        path.addQuadCurve(to: p(0.79, 0.93), control: p(0.835, 0.93))
        path.closeSubpath()
        return path
    }
}

extension Animation {
    /// Folders opening and closing.
    static let folderToggle = Animation.spring(duration: 0.2)
}

private struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isMarked: Bool
    /// The marked tabs, when this one is among two or more of them.
    let markedTabs: [BrowserTab.ID]
    let namespace: Namespace.ID
    let onSelect: () -> Void
    /// The marked tabs were used by a menu command.
    let onMarkedUsed: () -> Void
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(url: tab.url, size: 16)
            Text(tab.title).lineLimit(1).fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 0)
            if hovering && tab.isUnloaded != true {
                Button { pool.close(tab.id); store.closeTab(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        // A folder tab whose page was closed stays, dimmed, until it's opened again.
        .opacity(tab.isUnloaded == true ? 0.5 : 1)
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
            if markedTabs.count >= 2 {
                Button("Open \(min(markedTabs.count, Split.maxPanes)) Tabs in Split View") {
                    store.makeSplit(markedTabs)
                    onMarkedUsed()
                }
                Button("New Folder with \(markedTabs.count) Tabs") {
                    store.addFolder(tabs: markedTabs)
                    onMarkedUsed()
                }
            } else if let current = store.selectedTab?.id, current != tab.id {
                Button("Add to Split View") { store.addToSplit(tab.id, beside: current) }
            }
            Menu("Add to Folder") {
                ForEach(folderChoices, id: \.folder.id) { choice in
                    Button(String(repeating: "    ", count: choice.depth) + choice.folder.name) {
                        store.moveTabs(markedTabs.count >= 2 ? markedTabs : [tab.id], toFolder: choice.folder.id)
                        onMarkedUsed()
                    }
                    .disabled(choice.folder.id == tab.folderID)
                }
                if !folderChoices.isEmpty { Divider() }
                Button("New Folder") {
                    store.addFolder(tabs: markedTabs.count >= 2 ? markedTabs : [tab.id])
                    onMarkedUsed()
                }
            }
            if tab.folderID != nil {
                Button("Remove from Folder") { store.moveTabs([tab.id], toFolder: nil) }
            }
            Button("Add to Favorites") { store.addFavorite(from: tab) }
            Divider()
            Button("Close Tab") { pool.close(tab.id); store.closeTab(tab.id) }
        }
        .animation(.smooth(duration: 0.25), value: isSelected)
    }

    /// Every folder in the space, depth first, for the Add to Folder menu.
    private var folderChoices: [(folder: Folder, depth: Int)] {
        guard let space = store.selectedSpace else { return [] }
        func walk(_ parent: Folder.ID?, _ depth: Int) -> [(folder: Folder, depth: Int)] {
            space.subfolders(of: parent).flatMap { [($0, depth)] + walk($0.id, depth + 1) }
        }
        return walk(nil, 0)
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

/// Library and downloads on the left, one glyph per space in the middle, and the + menu on the right.
private struct BottomBar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var showsLibrary = false
    @State private var showsNewMenu = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { showsLibrary = true } label: { Image(systemName: "archivebox") }
                    .help("Library")
                    .popover(isPresented: $showsLibrary, arrowEdge: .top) { LibraryPopover(isPresented: $showsLibrary) }
                DownloadsButton()
            }
            .animation(.snappy(duration: 0.2), value: pool.downloads.isEmpty)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                // The active marker moves across during a swipe.
                let progress = store.swipeProgress
                let neighbor = store.neighborSpace(towardProgress: progress)?.id
                ForEach(store.spaces) { space in
                    SpaceGlyph(space: space,
                               activeAmount: space.id == store.selectedSpaceID ? 1 - abs(progress)
                                   : space.id == neighbor ? abs(progress) : 0)
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

/// A space as a plain glyph: its symbol, or its first letter. The active one is highlighted.
private struct SpaceGlyph: View {
    let space: Space
    /// 1 for the active space; between 0 and 1 while a swipe moves to or from it.
    let activeAmount: CGFloat
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false
    @State private var showsEditor = false
    @State private var confirmsDelete = false

    var body: some View {
        Button { store.selectSpace(space.id) } label: {
            ZStack {
                // Like Arc: the active space sits on a soft glass tile in full strength; the
                // others are dimmed. The theme color alone was too close to the sidebar's tint.
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
                    .opacity(activeAmount)
                glyph.foregroundStyle(.primary.opacity(hovering ? 0.65 : 0.35)).opacity(1 - activeAmount)
                glyph.foregroundStyle(.primary).opacity(activeAmount)
            }
            .frame(width: 30, height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(space.name)
        .contextMenu {
            Button("Edit Space…") { showsEditor = true }
            Picker("Profile", selection: Binding(get: { space.profileID }, set: { id in
                for page in store.setProfile(id, for: space.id) { pool.close(page) }
            })) {
                ForEach(store.profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            .pickerStyle(.menu)
            Button("Edit Profiles…") { openSettings() }
            Divider()
            Button("Delete Space…", role: .destructive) { confirmsDelete = true }
                .disabled(store.spaces.count < 2)
        }
        .popover(isPresented: $showsEditor, arrowEdge: .top) { EditSpacePopover(spaceID: space.id) }
        .confirmationDialog("Delete “\(space.name)”?", isPresented: $confirmsDelete) {
            Button("Delete Space", role: .destructive) {
                for page in store.deleteSpace(space.id) { pool.close(page) }
            }
        } message: {
            Text("Its tabs, folders and favorites are removed. Its profile and logins stay.")
        }
        .animation(.snappy(duration: 0.15), value: hovering)
    }

    private var glyph: some View {
        SpaceIconView(icon: space.icon, name: space.name, size: 15)
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
            MenuRow(icon: "folder.badge.plus", title: "New Folder", shortcut: "⌥⌘N") { run { store.addFolder() } }
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

/// The site's own icon once a page has shown it, otherwise its first letter on a tile.
struct FaviconView: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Group {
            if let image = FaviconCache.shared.image(for: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(.quaternary)
                    .overlay {
                        Text(letter).font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.25))
    }

    private var letter: String {
        let host = (url.host() ?? "").replacingOccurrences(of: "www.", with: "")
        return host.first.map { String($0).uppercased() } ?? ""
    }
}
