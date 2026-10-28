import SwiftUI

/// What a space shows when nothing is open in it: the time, a search field that opens the
/// command bar, the space's favorites (or most visited sites), pages to jump back into and a
/// few actions, all on the space's own colors. Typing anywhere starts a search.
struct NewTabPage: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool
    @State private var appeared = false
    /// Worked out when the space or its history changes, not on every redraw: most visited
    /// goes through up to 20,000 pages.
    @State private var recent: [HistoryEntry] = []
    @State private var topSites: [HistoryEntry] = []

    var body: some View {
        let space = store.selectedSpace
        let theme = store.draftTheme ?? space?.resolvedTheme ?? SpaceTheme(tint: .graphite)
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 34) {
                    header(space: space)
                        .reveal(appeared, delay: 0)
                    searchField
                        .reveal(appeared, delay: 0.05)
                    if let space, !space.favorites.isEmpty {
                        TileRows(items: space.favorites.map { .favorite($0) })
                            .reveal(appeared, delay: 0.1)
                    } else if !topSites.isEmpty {
                        section("Most visited") { TileRows(items: topSites.map { .site($0) }) }
                            .reveal(appeared, delay: 0.1)
                    }
                    if !recent.isEmpty {
                        section("Jump back in") { RecentGrid(entries: recent) }
                            .reveal(appeared, delay: 0.15)
                    }
                    actions(space: space)
                        .reveal(appeared, delay: 0.2)
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                // Centered while it fits; scrolls once the window is short.
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            let wallpaper = space?.resolvedWallpaper ?? .default
            ZStack {
                if wallpaper == .none {
                    NewTabBackground(theme: theme)
                } else {
                    WallpaperView(wallpaper: wallpaper, theme: theme, seed: space?.id ?? Self.fallbackSeed)
                    WallpaperVeil(theme: theme)
                }
            }
            .id(wallpaper)
            .transition(.opacity)
            .animation(.smooth(duration: 0.4), value: wallpaper)
        }
        .overlay(alignment: .bottomTrailing) {
            if let space { wallpaperMenu(space) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down, action: startTyping)
        .onAppear {
            focused = true
            withAnimation(.smooth(duration: 0.5)) { appeared = true }
        }
        .onChange(of: store.isCommandBarOpen) { _, open in if !open { focused = true } }
        .task(id: Suggestions.Key(space: space, historyCount: pool.history.entries.count)) { loadSuggestions(space) }
    }

    // MARK: Header

    private func header(space: Space?) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 7) {
                    Text(Self.greeting(at: context.date))
                    Text("·").foregroundStyle(.tertiary)
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    if let space {
                        Text("·").foregroundStyle(.tertiary)
                        SpaceIconView(icon: space.icon, name: space.name, size: 12)
                            .foregroundStyle(space.accent)
                        Text(space.name)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    // MARK: Search

    private var searchField: some View {
        Button { openCommandBar() } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Search or enter address")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                KeyCap("⌘T")
            }
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .frame(height: 56)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: 560)
        .help("Search, open a site, or switch tabs")
    }

    private func openCommandBar(typing text: String = "") {
        store.commandBarSeed = text
        store.isCommandBarOpen = true
    }

    /// The first key typed on the page opens the command bar with it.
    private func startTyping(_ press: KeyPress) -> KeyPress.Result {
        guard !store.isCommandBarOpen,
              press.modifiers.isDisjoint(with: [.command, .control, .option]),
              let character = press.characters.first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return .ignored }
        openCommandBar(typing: press.characters)
        return .handled
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func actions(space: Space?) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let closed = space?.recentlyClosed?.last {
                    ActionChip(title: "Reopen \(closed.title)", symbol: "arrow.uturn.backward") {
                        store.reopenLastClosedTab()
                    }
                    .frame(maxWidth: 220)
                }
                ActionChip(title: "History", symbol: "clock") { openWindow(id: "history") }
                ActionChip(title: "New Space", symbol: "plus.square.on.square") {
                    withAnimation(.snappy) { store.isCreatingSpace = true }
                }
                if !store.isPrivate {
                    ActionChip(title: "Private Window", symbol: "eyeglasses") { openWindow(id: "private") }
                }
            }
        }
    }

    // MARK: Wallpaper

    /// Seeds the wallpaper while no space is selected.
    private static let fallbackSeed = UUID(uuidString: "6A3F0C55-2B1E-4D8A-9C47-1E5B7F2D9A10")!

    private func wallpaperMenu(_ space: Space) -> some View {
        let selection = Binding<Wallpaper>(
            get: { space.resolvedWallpaper },
            set: { wallpaper in store.updateSpace(space.id) { $0.wallpaper = wallpaper } }
        )
        return Menu {
            Picker("Background", selection: selection) {
                ForEach(Wallpaper.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Change this space's background")
        .padding(16)
    }

    // MARK: Suggestions

    private enum Suggestions {
        struct Key: Equatable {
            var spaceID: Space.ID?
            var favorites: [URL]
            var tabs: [URL]
            var historyCount: Int

            init(space: Space?, historyCount: Int) {
                spaceID = space?.id
                favorites = space?.favorites.map(\.url) ?? []
                tabs = space?.tabs.map(\.url) ?? []
                self.historyCount = historyCount
            }
        }
    }

    private func loadSuggestions(_ space: Space?) {
        guard let space, !store.isPrivate else {
            recent = []
            topSites = []
            return
        }
        let history = pool.history.history
        let shown = Set(space.favorites.map { History.site(of: $0.url) } + space.tabs.map { History.site(of: $0.url) })
        topSites = space.favorites.isEmpty ? history.topSites(profileID: space.profileID, excluding: shown, limit: 6) : []
        recent = history.recentSites(profileID: space.profileID,
                                     excluding: shown.union(topSites.map { History.site(of: $0.url) }), limit: 6)
    }
}

// MARK: - Pieces

/// The page's own colors: a light veil over the window's theme, so it still reads as the page,
/// with the space's colors glowing through from the corners.
private struct NewTabBackground: View {
    let theme: SpaceTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = theme.gradientColors
        ZStack {
            Rectangle().fill(.background).opacity(colorScheme == .dark ? 0.62 : 0.5)
            RadialGradient(colors: [theme.accent.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [(colors.last ?? theme.accent).opacity(0.28), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 640)
            if theme.grain > 0 {
                Grain.image.resizable(resizingMode: .tile).opacity(theme.grain * 0.2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Over a wallpaper: the page's middle fades a little toward the background, so the clock and
/// the cards over it read on any colors.
private struct WallpaperVeil: View {
    let theme: SpaceTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let background = WallpaperPalette(theme: theme, isDark: colorScheme == .dark).background[0]
        RadialGradient(colors: [background.color(intensity: theme.intensity).opacity(colorScheme == .dark ? 0.5 : 0.6), .clear],
                       center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 560)
            .allowsHitTesting(false)
    }
}

/// A big site tile: a favorite, or a most visited site.
private enum TileItem: Identifiable {
    case favorite(Favorite), site(HistoryEntry)

    var id: String {
        switch self {
        case .favorite(let favorite): "fav-\(favorite.id)"
        case .site(let entry): "site-\(entry.id)"
        }
    }

    var url: URL {
        switch self {
        case .favorite(let favorite): favorite.tab?.url ?? favorite.url
        case .site(let entry): entry.url
        }
    }

    var title: String {
        switch self {
        case .favorite(let favorite): favorite.title
        case .site(let entry): Self.shortTitle(entry.title, url: entry.url)
        }
    }

    /// Page titles run long ("Inbox (3) - me@example.com - Gmail"); a tile shows the site's name.
    private static func shortTitle(_ title: String, url: URL) -> String {
        let parts = title.split(separator: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = parts.last, parts.count > 1, last.count <= 24 { return last }
        if title.count <= 18 { return title }
        return History.site(of: url)
    }
}

/// Tiles in centered rows of up to six.
private struct TileRows: View {
    let items: [TileItem]
    static let perRow = 6

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: Self.perRow).map { Array(items[$0..<min($0 + Self.perRow, items.count)]) }
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 18) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 16) {
                        ForEach(rows[i]) { SiteTile(item: $0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SiteTile: View {
    let item: TileItem
    @Environment(BrowserStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 9) {
                FaviconView(url: item.url, size: 30)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .frame(width: 68, height: 68)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 84)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressShrinks())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .help(item.url.absoluteString)
        .contextMenu {
            Button("Open in New Tab") { store.openTab(item.url, title: item.title) }
            Button("Copy Link") { copy(item.url) }
        }
    }

    private func open() {
        switch item {
        case .favorite(let favorite): store.selectFavorite(favorite.id)
        case .site(let entry): store.openTab(entry.url, title: entry.title)
        }
    }
}

/// Recently visited pages, two to a row.
private struct RecentGrid: View {
    let entries: [HistoryEntry]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(entries) { RecentCard(entry: $0) }
        }
    }
}

private struct RecentCard: View {
    let entry: HistoryEntry
    @Environment(BrowserStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button { store.openTab(entry.url, title: entry.title) } label: {
            HStack(spacing: 12) {
                FaviconView(url: entry.url, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(PressShrinks(scale: 0.98))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .help(entry.url.absoluteString)
        .contextMenu {
            Button("Copy Link") { copy(entry.url) }
        }
    }

    private var subtitle: String {
        let ago = entry.lastVisited.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(History.site(of: entry.url)) · \(ago)"
    }
}

private struct ActionChip: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(.capsule)
        }
        .buttonStyle(PressShrinks(scale: 0.96))
        .foregroundStyle(.secondary)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// A keyboard shortcut drawn as a key.
private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.primary.opacity(0.07), in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct PressShrinks: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
}

private extension View {
    /// Fades and rises into place when the page appears, each section a moment after the last.
    func reveal(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(.smooth(duration: 0.5).delay(delay), value: shown)
    }
}
