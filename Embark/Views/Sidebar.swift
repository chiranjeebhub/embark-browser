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
        .padding(.vertical, 12)
    }
}

private struct NavigationRow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        let page = pool.existingPage(for: store.selectedTab?.id)
        let _ = pool.revision
        HStack(spacing: 2) {
            Spacer()
            Button { page?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!(page?.canGoBack ?? false))
            Button { page?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!(page?.canGoForward ?? false))
            Button { page?.reload() } label: { Image(systemName: "arrow.clockwise") }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: 22)
        .padding(.leading, 70) // traffic lights
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
                                Text(space.name.prefix(1))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(space.tint.color, in: .circle)
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

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Side project"))
            Picker("Color", selection: $tint) {
                ForEach(SpaceTint.allCases, id: \.self) { tint in
                    Label(tint.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(tint.color).tag(tint)
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
                Button("Create") { store.addSpace(name: name.isEmpty ? "New Space" : name, tint: tint); dismiss() }
                    .buttonStyle(.glassProminent)
            }
        }
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
