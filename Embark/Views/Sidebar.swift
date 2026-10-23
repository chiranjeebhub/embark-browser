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

struct NavigationRow: View {
    /// Pushes the page buttons to the sidebar's right edge; off when the sidebar is hidden.
    var spread = true
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
            if spread { Spacer() }
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

/// Each space's own favorites. These are its pinned sites; there is no separate pinned list.
private struct FavoritesGrid: View {
    let favorites: [Favorite]
    @Environment(BrowserStore.self) private var store

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(favorites) { favorite in
                    Button { store.openFavorite(favorite) } label: {
                        FaviconView(url: favorite.url, size: 22)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    .help(favorite.title)
                    .contextMenu {
                        Button("Remove from Favorites", role: .destructive) { store.removeFavorite(favorite.id) }
                    }
                }
            }
        }
    }
}

private struct TabList: View {
    let space: Space
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Namespace private var selection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Button { store.isCommandBarOpen = true } label: {
                    Label("New Tab", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                ForEach(space.tabs) { tab in
                    TabRow(tab: tab, isSelected: tab.id == space.selectedTabID, namespace: selection)
                }
            }
            .font(.system(size: 13))
        }
        .scrollIndicators(.never)
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
