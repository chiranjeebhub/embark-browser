import SwiftUI

struct Sidebar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationRow()
            AddressPill()
            if let space = store.selectedSpace {
                FavoritesGrid(favorites: space.favorites)
                Divider().padding(.horizontal, 8)
                TabList(space: space)
            }
            Spacer(minLength: 0)
            SpaceSwitcher()
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.bottom, 12)
    }
}

extension Animation {
    /// Showing and hiding the sidebar should feel instant.
    static let sidebar = Animation.snappy(duration: 0.16)
}

private struct NavigationRow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        let page = pool.existingPage(for: store.selectedTab?.id)
        let _ = pool.revision
        // Shares the title bar row with the traffic lights, so the sidebar starts at the top.
        HStack(spacing: 6) {
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
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .frame(height: 30)
        .padding(.leading, 72) // traffic lights
    }
}

private struct AddressPill: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Button { store.isCommandBarOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: store.selectedTab?.url.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(store.selectedTab?.url.host() ?? "Search or enter address")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }
}

/// What a drag inside the sidebar carries. Sent as a plain string so no custom type needs
/// registering; anything else dropped on the sidebar is ignored.
private enum SidebarDrag: Equatable {
    case tab(BrowserTab.ID)
    case favorite(Favorite.ID)

    /// The drag in progress, so drop targets can show its placeholder while hovering. Drops
    /// themselves trust only the dragged string, since this can be stale after a cancelled drag.
    @MainActor static var current: SidebarDrag?

    var token: String {
        switch self {
        case .tab(let id): "embark-tab:\(id.uuidString)"
        case .favorite(let id): "embark-favorite:\(id.uuidString)"
        }
    }

    init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "embark-tab": self = .tab(id)
        case "embark-favorite": self = .favorite(id)
        default: return nil
        }
    }

    @MainActor func url(in space: Space) -> URL? {
        switch self {
        case .tab(let id): space.tabs.first { $0.id == id }?.url
        case .favorite(let id): space.favorites.first { $0.id == id }?.url
        }
    }

    /// Starts dragging this item; used with `.onDrag`.
    @MainActor func itemProvider() -> NSItemProvider {
        Self.current = self
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
        .onDrag { SidebarDrag.favorite(favorite.id).itemProvider() }
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

        func validateDrop(info: DropInfo) -> Bool { SidebarDrag.current != nil }

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
                    case nil: break
                    }
                }
                SidebarDrag.current = nil
            }
        }
    }
}

/// Open tabs. Dragging a tab or favorite over the list opens a row-height gap at the drop spot.
private struct TabList: View {
    let space: Space
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Namespace private var selection
    /// The gap's index among the rows, while a drag hovers the list.
    @State private var gap: Int?

    private static let headerHeight: CGFloat = 34
    private static let rowHeight: CGFloat = 36
    private static let spacing: CGFloat = 2

    private enum Row: Identifiable {
        case tab(BrowserTab), gap
        var id: String {
            switch self {
            case .tab(let tab): tab.id.uuidString
            case .gap: "gap"
            }
        }
    }

    /// Tabs other than the one being dragged, which gives up its row to the gap.
    private var staying: [BrowserTab] {
        space.tabs.filter { gap == nil || SidebarDrag.current != .tab($0.id) }
    }

    private var rows: [Row] {
        var rows = staying.map(Row.tab)
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
                        TabRow(tab: tab, isSelected: tab.id == space.selectedTabID, namespace: selection)
                            .onDrag { SidebarDrag.tab(tab.id).itemProvider() }
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
            let index = list.gap ?? list.staying.count
            let tabs = list.space.tabs, store = list.store, gap = list.$gap
            return SidebarDrag.load(from: info) { drag in
                withAnimation(.dropReflow) {
                    gap.wrappedValue = nil
                    switch drag {
                    case .tab(let id):
                        let from = tabs.firstIndex { $0.id == id } ?? index
                        store.moveTab(id, before: index >= from ? index + 1 : index)
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
    let namespace: Namespace.ID
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
            }
        }
        .contentShape(.rect)
        .onTapGesture { store.selectTab(tab.id) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Add to Favorites") { store.addFavorite(from: tab) }
            Button("Open in Split View") { store.splitTabID = tab.id }
            Divider()
            Button("Close Tab") { pool.close(tab.id); store.closeTab(tab.id) }
        }
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}

/// One glass capsule: the active space expands to show its name, the others are lettered dots.
private struct SpaceSwitcher: View {
    @Environment(BrowserStore.self) private var store
    @State private var isAdding = false
    @Namespace private var glass

    var body: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(store.spaces) { space in
                        let active = space.id == store.selectedSpaceID
                        Button { store.selectSpace(space.id) } label: {
                            HStack(spacing: 7) {
                                SpaceBadge(name: space.name, icon: space.icon, tint: space.tint, size: 24)
                                if active {
                                    Text(space.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                }
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, active ? 12 : 4)
                            .frame(height: 32)
                            .frame(maxWidth: active ? .infinity : nil, alignment: .leading)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .background {
                            if active {
                                Color.clear
                                    .glassEffect(.regular.tint(.white.opacity(0.5)), in: .capsule)
                                    .glassEffectID("active-space", in: glass)
                            }
                        }
                        .help("\(space.name) space, own profile")
                        .contextMenu {
                            Menu("Icon") {
                                Button("First Letter") { store.setIcon(nil, for: space.id) }
                                Divider()
                                ForEach(SpaceIcon.choices, id: \.self) { symbol in
                                    Button { store.setIcon(symbol, for: space.id) } label: { Image(systemName: symbol) }
                                }
                            }
                        }
                    }
                }
                .padding(4)
                .glassEffect(.regular, in: .capsule)
            }
            Button { isAdding = true } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("New space with its own profile")
        }
        .animation(.smooth(duration: 0.3), value: store.selectedSpaceID)
        .sheet(isPresented: $isAdding) { NewSpaceSheet() }
    }
}

private struct NewSpaceSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tint = SpaceTint.teal
    @State private var icon: String? = SpaceIcon.choices[0]

    var body: some View {
        Form {
            HStack {
                Spacer()
                SpaceBadge(name: name.isEmpty ? "N" : name, icon: icon, tint: tint, size: 44)
                Spacer()
            }
            TextField("Name", text: $name, prompt: Text("Side project"))
            Picker("Color", selection: $tint) {
                ForEach(SpaceTint.allCases, id: \.self) { tint in
                    Label(tint.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(tint.color).tag(tint)
                }
            }
            LabeledContent("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 8), spacing: 4) {
                    IconChoice(symbol: nil, label: String(name.prefix(1)).uppercased(), selection: $icon, tint: tint)
                    ForEach(SpaceIcon.choices, id: \.self) { symbol in
                        IconChoice(symbol: symbol, label: nil, selection: $icon, tint: tint)
                    }
                }
            }
            Text("A new space gets its own profile, so you can sign in to a different account.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { store.addSpace(name: name.isEmpty ? "New Space" : name, tint: tint, icon: icon); dismiss() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// The round tinted mark for a space: its icon, or the first letter of its name.
struct SpaceBadge: View {
    let name: String
    let icon: String?
    let tint: SpaceTint
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(systemName: icon).font(.system(size: size * 0.46, weight: .semibold))
            } else {
                Text(name.prefix(1).uppercased()).font(.system(size: size * 0.46, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(tint.color.gradient, in: .circle)
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
