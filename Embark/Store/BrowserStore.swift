import Foundation
import Observation

/// All browser state: profiles, spaces, favorites and tabs. Saved to Application Support as JSON.
@Observable
final class BrowserStore {
    var profiles: [Profile] = [] { didSet { save() } }
    var spaces: [Space] = [] { didSet { save() } }
    var selectedSpaceID: Space.ID? { didSet { save() } }
    var isCommandBarOpen = false
    var isSidebarVisible = true
    /// The tab shown on the right in split view, if any.
    var splitTabID: BrowserTab.ID?
    /// The sidebar shows the Create a Space form instead of favorites and tabs.
    var isCreatingSpace = false
    /// The tint picked in the Create a Space form, previewed on the window until it's created.
    var draftTint: SpaceTint?

    static let recentlyClosedLimit = 20

    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let fileURL = BrowserStore.supportDirectory.appending(path: "state.json")

    static let supportDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Embark", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        load()
        if spaces.isEmpty { seed() }
    }

    // MARK: Selection

    var selectedSpace: Space? {
        get { spaces.first { $0.id == selectedSpaceID } }
        set {
            guard let newValue, let i = spaces.firstIndex(where: { $0.id == newValue.id }) else { return }
            spaces[i] = newValue
        }
    }

    var selectedTab: BrowserTab? {
        guard let space = selectedSpace else { return nil }
        return space.tabs.first { $0.id == space.selectedTabID }
    }

    func profile(for space: Space) -> Profile? {
        profiles.first { $0.id == space.profileID }
    }

    func selectSpace(_ id: Space.ID) { selectedSpaceID = id }

    func selectSpace(offset: Int) {
        guard let current = spaces.firstIndex(where: { $0.id == selectedSpaceID }), !spaces.isEmpty else { return }
        selectedSpaceID = spaces[(current + offset + spaces.count) % spaces.count].id
    }

    func selectTab(_ id: BrowserTab.ID) {
        mutateSelectedSpace { space in
            space.selectedTabID = id
            if let i = space.tabs.firstIndex(where: { $0.id == id }) { space.tabs[i].lastActive = .now }
        }
    }

    // MARK: Tabs

    @discardableResult
    func openTab(_ url: URL, title: String? = nil) -> BrowserTab {
        let tab = BrowserTab(title: title ?? url.host() ?? url.absoluteString, url: url)
        mutateSelectedSpace { space in
            space.tabs.insert(tab, at: 0)
            space.selectedTabID = tab.id
        }
        return tab
    }

    func closeTab(_ id: BrowserTab.ID) {
        mutateSelectedSpace { space in
            guard let i = space.tabs.firstIndex(where: { $0.id == id }) else { return }
            let closed = space.tabs.remove(at: i)
            space.recentlyClosed = Array(((space.recentlyClosed ?? []) + [closed]).suffix(Self.recentlyClosedLimit))
            if space.selectedTabID == id {
                space.selectedTabID = space.tabs.indices.contains(i) ? space.tabs[i].id : space.tabs.last?.id
            }
        }
        if splitTabID == id { splitTabID = nil }
    }

    /// Reopens a tab from the Library and takes it off the recently closed list.
    func reopenClosedTab(_ id: BrowserTab.ID) {
        guard let tab = selectedSpace?.recentlyClosed?.first(where: { $0.id == id }) else { return }
        mutateSelectedSpace { $0.recentlyClosed?.removeAll { $0.id == id } }
        openTab(tab.url, title: tab.title)
    }

    /// Split shows the most recently used other tab beside the current one; again closes it.
    func toggleSplit() {
        if splitTabID != nil { splitTabID = nil; return }
        guard let space = selectedSpace else { return }
        splitTabID = space.tabs
            .filter { $0.id != space.selectedTabID }
            .max { $0.lastActive < $1.lastActive }?.id
    }

    func updateTab(_ id: BrowserTab.ID, title: String?, url: URL?) {
        for s in spaces.indices {
            guard let t = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            if let title, !title.isEmpty { spaces[s].tabs[t].title = title }
            if let url { spaces[s].tabs[t].url = url }
        }
    }

    // MARK: Favorites

    func addFavorite(from tab: BrowserTab) {
        mutateSelectedSpace { $0.favorites.append(Favorite(title: tab.title, url: tab.url)) }
    }

    func removeFavorite(_ id: Favorite.ID) {
        mutateSelectedSpace { $0.favorites.removeAll { $0.id == id } }
    }

    /// Opening a favorite reuses its tab if one is already open, so favorites behave like apps.
    func openFavorite(_ favorite: Favorite) {
        if let existing = selectedSpace?.tabs.first(where: { $0.url.host() == favorite.url.host() }) {
            selectTab(existing.id)
        } else {
            openTab(favorite.url, title: favorite.title)
        }
    }

    // MARK: Dragging between tabs and favorites

    /// Pins a tab as a favorite before `index` (or at the end). The tab stays open.
    func pinTab(_ id: BrowserTab.ID, at index: Int?) {
        mutateSelectedSpace { space in
            guard let tab = space.tabs.first(where: { $0.id == id }),
                  !space.favorites.contains(where: { $0.url == tab.url }) else { return }
            space.favorites.insert(Favorite(title: tab.title, url: tab.url), at: Self.clamp(index, space.favorites.count))
        }
    }

    /// Unpins a favorite, keeping it as a tab before `index`: its open tab moves there, or one is opened.
    func unpinFavorite(_ id: Favorite.ID, toTabAt index: Int?) {
        mutateSelectedSpace { space in
            guard let favorite = space.favorites.first(where: { $0.id == id }) else { return }
            space.favorites.removeAll { $0.id == id }
            if let i = space.tabs.firstIndex(where: { $0.url.host() == favorite.url.host() }) {
                let tab = space.tabs.remove(at: i)
                space.tabs.insert(tab, at: Self.clamp(index.map { $0 > i ? $0 - 1 : $0 }, space.tabs.count))
            } else {
                let tab = BrowserTab(title: favorite.title, url: favorite.url)
                space.tabs.insert(tab, at: Self.clamp(index, space.tabs.count))
                space.selectedTabID = tab.id
            }
        }
    }

    func moveFavorite(_ id: Favorite.ID, before index: Int?) {
        mutateSelectedSpace { Self.move(id, before: index, in: &$0.favorites) }
    }

    func moveTab(_ id: BrowserTab.ID, before index: Int?) {
        mutateSelectedSpace { Self.move(id, before: index, in: &$0.tabs) }
    }

    private static func move<Item: Identifiable>(_ id: Item.ID, before index: Int?, in items: inout [Item]) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: clamp(index.map { $0 > from ? $0 - 1 : $0 }, items.count))
    }

    private static func clamp(_ index: Int?, _ count: Int) -> Int {
        min(max(index ?? count, 0), count)
    }

    // MARK: Spaces

    /// Adds a space and switches to it. With no `profileID` it gets a new profile of its own;
    /// otherwise it shares that profile's logins.
    func addSpace(name: String, tint: SpaceTint, icon: String?, profileID: Profile.ID? = nil) {
        var profileID = profileID
        if profileID == nil {
            let profile = Profile(name: name)
            profiles.append(profile)
            profileID = profile.id
        }
        let space = Space(name: name, tint: tint, icon: icon, profileID: profileID!)
        spaces.append(space)
        selectedSpaceID = space.id
    }

    func setIcon(_ icon: String?, for id: Space.ID) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[i].icon = icon
    }

    // MARK: Persistence

    private func mutateSelectedSpace(_ body: (inout Space) -> Void) {
        guard let i = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        body(&spaces[i])
    }

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var spaces: [Space]
        var selectedSpaceID: Space.ID?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isLoading = true
        profiles = snapshot.profiles
        spaces = snapshot.spaces
        selectedSpaceID = snapshot.selectedSpaceID ?? snapshot.spaces.first?.id
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Snapshot(profiles: profiles, spaces: spaces, selectedSpaceID: selectedSpaceID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seed() {
        isLoading = true
        let personal = Profile(name: "Personal")
        let work = Profile(name: "Work")
        profiles = [personal, work]
        func fav(_ title: String, _ url: String) -> Favorite { Favorite(title: title, url: URL(string: url)!) }
        spaces = [
            Space(name: "Personal", tint: .purple, icon: "house.fill", profileID: personal.id, favorites: [
                fav("Gmail", "https://mail.google.com"),
                fav("YouTube", "https://www.youtube.com"),
                fav("WhatsApp", "https://web.whatsapp.com"),
                fav("Maps", "https://maps.google.com"),
            ]),
            Space(name: "Work", tint: .blue, icon: "briefcase.fill", profileID: work.id, favorites: [
                fav("Gmail", "https://mail.google.com"),
                fav("Calendar", "https://calendar.google.com"),
                fav("Slack", "https://app.slack.com"),
                fav("GitHub", "https://github.com"),
            ]),
        ]
        selectedSpaceID = spaces.first?.id
        isLoading = false
        save()
    }
}
