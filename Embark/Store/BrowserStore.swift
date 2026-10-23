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
            space.tabs.remove(at: i)
            if space.selectedTabID == id {
                space.selectedTabID = space.tabs.indices.contains(i) ? space.tabs[i].id : space.tabs.last?.id
            }
        }
        if splitTabID == id { splitTabID = nil }
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

    // MARK: Spaces

    func addSpace(name: String, tint: SpaceTint, icon: String?) {
        let profile = Profile(name: name)
        profiles.append(profile)
        let space = Space(name: name, tint: tint, icon: icon, profileID: profile.id)
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
