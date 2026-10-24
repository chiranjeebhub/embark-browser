import Foundation

/// Favorites as their own tabs, as in Arc: selecting one shows its own page (the tab list then
/// has no selected tab), pinning a tab moves it, page and all, into the favorites, and
/// unpinning moves it back. Kept on `Space` so it can be tested without the store.
extension Space {
    /// A tab in the tab list or a favorite's page.
    func pageTab(_ id: BrowserTab.ID?) -> BrowserTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id } ?? favorites.lazy.compactMap(\.tab).first { $0.id == id }
    }

    /// The favorite whose page has this id.
    func favorite(withPage id: BrowserTab.ID?) -> Favorite? {
        guard let id else { return nil }
        return favorites.first { $0.tab?.id == id }
    }

    /// Shows a favorite's own page, making it on first use. Returns the page's tab id.
    @discardableResult
    mutating func selectFavorite(_ id: Favorite.ID) -> BrowserTab.ID? {
        guard let i = favorites.firstIndex(where: { $0.id == id }) else { return nil }
        var tab = favorites[i].tab ?? BrowserTab(title: favorites[i].title, url: favorites[i].url)
        tab.lastActive = .now
        tab.isUnloaded = nil
        favorites[i].tab = tab
        selectedTabID = tab.id
        return tab.id
    }

    /// Moves a tab into the favorites before `index` (or last). It keeps its id, so its page
    /// carries on without reloading, and stays selected if it was.
    @discardableResult
    mutating func pinTab(_ id: BrowserTab.ID, at index: Int?) -> Bool {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return false }
        var tab = tabs.remove(at: i)
        tab.folderID = nil
        tab.isUnloaded = nil
        leaveSplit(id)
        let favorite = Favorite(title: tab.title, url: tab.url, tab: tab)
        favorites.insert(favorite, at: Self.clamp(index, favorites.count))
        return true
    }

    /// Moves a favorite back to the tab list, page and all, before `index` (or last).
    @discardableResult
    mutating func unpinFavorite(_ id: Favorite.ID, toTabAt index: Int?) -> BrowserTab.ID? {
        guard let i = favorites.firstIndex(where: { $0.id == id }) else { return nil }
        let favorite = favorites.remove(at: i)
        var tab = favorite.tab ?? BrowserTab(title: favorite.title, url: favorite.url)
        tab.folderID = nil
        tabs.insert(tab, at: Self.clamp(index, tabs.count))
        return tab.id
    }

    /// Records a page's new title or address, for a tab or a favorite's page.
    mutating func updatePage(_ id: BrowserTab.ID, title: String?, url: URL?) {
        if let i = tabs.firstIndex(where: { $0.id == id }) {
            if let title, !title.isEmpty { tabs[i].title = title }
            if let url { tabs[i].url = url }
        } else if let i = favorites.firstIndex(where: { $0.tab?.id == id }) {
            if let title, !title.isEmpty { favorites[i].tab?.title = title }
            if let url { favorites[i].tab?.url = url }
        }
    }

    /// Closing a favorite's page unloads it; the favorite stays. Selects a loaded tab instead.
    mutating func unloadFavoritePage(_ id: BrowserTab.ID) {
        guard let i = favorites.firstIndex(where: { $0.tab?.id == id }) else { return }
        favorites[i].tab?.isUnloaded = true
        if selectedTabID == id { selectedTabID = tabs.first { $0.isUnloaded != true }?.id }
    }

    private mutating func leaveSplit(_ id: BrowserTab.ID) {
        splits = splits?.compactMap { split in
            var split = split
            split.tabIDs.removeAll { $0 == id }
            guard split.tabIDs.count >= 2 else { return nil }
            split.evenOut()
            return split
        }
    }

    private static func clamp(_ index: Int?, _ count: Int) -> Int {
        min(max(index ?? count, 0), count)
    }
}
