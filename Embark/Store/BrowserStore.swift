import AppKit
import Observation

/// One window's view of the browser: its selected space and what its sidebar and command bar
/// are doing. Profiles, spaces, favorites and tabs live in the shared `BrowserLibrary`, so
/// every window sees the same ones.
@Observable
final class BrowserStore {
    let library: BrowserLibrary
    var profiles: [Profile] {
        get { library.profiles }
        set { library.profiles = newValue }
    }
    var spaces: [Space] {
        get { library.spaces }
        set { library.spaces = newValue }
    }
    var selectedSpaceID: Space.ID? { didSet { library.lastSelectedSpaceID = selectedSpaceID } }
    var isCommandBarOpen = false
    /// Bumped when a sidebar drag ends, however it ends, so drop targets clear leftover
    /// placeholders and highlights.
    var dragEndCount = 0
    /// How far a two-finger swipe has moved the sidebar, as a fraction of its width:
    /// positive reveals the previous space, negative the next one.
    var swipeProgress: CGFloat = 0
    var isSidebarVisible = true
    /// The next tab opened from the command bar joins this tab in a split (New Split).
    var pendingSplitTabID: BrowserTab.ID?
    /// The sidebar shows the Create a Space form instead of favorites and tabs.
    var isCreatingSpace = false
    /// The theme picked in the Create a Space form, previewed on the window until it's created.
    var draftTheme: SpaceTheme?
    /// The folder whose name is being edited in the tab list.
    var renamingFolderID: Folder.ID?

    static let recentlyClosedLimit = 20

    static let supportDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Embark", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A window showing `spaceID`, or the space used last.
    /// `isWindow` is false for the store behind History and Settings.
    init(library: BrowserLibrary = .shared, spaceID: Space.ID? = nil, isWindow: Bool = true) {
        self.library = library
        selectedSpaceID = spaceID ?? library.lastSelectedSpaceID ?? library.spaces.first?.id
        if isWindow { Self.windows.add(self) }
    }

    /// Every window's store, so a new window can pick a space no other window shows.
    nonisolated(unsafe) private static let windows = NSHashTable<BrowserStore>.weakObjects()

    /// A private window, with its own private space and profile.
    static func privateWindow() -> BrowserStore {
        BrowserStore(library: BrowserLibrary(privateWindow: ()), isWindow: false)
    }

    var isPrivate: Bool { profiles.contains { $0.isPrivate == true } }

    /// The space used last, unless another window shows it; then the first space no window
    /// shows, so two windows don't fight over the same page.
    static func forNewWindow(library: BrowserLibrary = .shared) -> BrowserStore {
        let shown = Set(windows.allObjects.compactMap(\.selectedSpaceID))
        let preferred = library.lastSelectedSpaceID ?? library.spaces.first?.id
        let spaceID = preferred.flatMap { shown.contains($0) ? nil : $0 }
            ?? library.spaces.first { !shown.contains($0.id) }?.id ?? preferred
        return BrowserStore(library: library, spaceID: spaceID)
    }

    // MARK: Selection

    var selectedSpace: Space? {
        get { spaces.first { $0.id == selectedSpaceID } }
        set {
            guard let newValue, let i = spaces.firstIndex(where: { $0.id == newValue.id }) else { return }
            spaces[i] = newValue
        }
    }

    /// The page on screen: a tab, or a favorite's own page.
    var selectedTab: BrowserTab? {
        guard let space = selectedSpace else { return nil }
        return space.pageTab(space.selectedTabID)
    }

    /// The selected favorite, when a favorite's page is on screen.
    var selectedFavorite: Favorite? {
        selectedSpace.flatMap { $0.favorite(withPage: $0.selectedTabID) }
    }

    func profile(for space: Space) -> Profile? {
        profiles.first { $0.id == space.profileID }
    }

    func selectSpace(_ id: Space.ID) { selectedSpaceID = id }

    /// The space a swipe at `progress` reveals, if there is one (swipes don't wrap around).
    func neighborSpace(towardProgress progress: CGFloat) -> Space? {
        guard progress != 0, let i = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return nil }
        let j = progress > 0 ? i - 1 : i + 1
        return spaces.indices.contains(j) ? spaces[j] : nil
    }

    func selectSpace(offset: Int) {
        guard let current = spaces.firstIndex(where: { $0.id == selectedSpaceID }), !spaces.isEmpty else { return }
        selectedSpaceID = spaces[(current + offset + spaces.count) % spaces.count].id
    }

    func selectTab(_ id: BrowserTab.ID) {
        if let favorite = selectedSpace?.favorite(withPage: id) { selectFavorite(favorite.id); return }
        mutateSelectedSpace { space in
            space.selectedTabID = id
            if let i = space.tabs.firstIndex(where: { $0.id == id }) {
                space.tabs[i].lastActive = .now
                // Selecting an unloaded folder tab opens its page again.
                space.tabs[i].isUnloaded = nil
            }
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
        // A favorite's page only unloads; the favorite stays.
        if selectedSpace?.favorite(withPage: id) != nil {
            mutateSelectedSpace { $0.unloadFavoritePage(id) }
            return
        }
        // Like Arc, a folder's tab is kept: closing only unloads its page.
        if selectedSpace?.tabs.first(where: { $0.id == id })?.folderID != nil, split(containing: id) == nil {
            mutateSelectedSpace { space in
                guard let i = space.tabs.firstIndex(where: { $0.id == id }) else { return }
                space.tabs[i].isUnloaded = true
                if space.selectedTabID == id {
                    space.selectedTabID = space.tabs.first { $0.id != id && $0.isUnloaded != true }?.id
                }
            }
            return
        }
        // Closing a split's pane focuses another pane of that split.
        let otherPane = split(containing: id)?.tabIDs.first { $0 != id }
        mutateSelectedSpace { space in
            guard let i = space.tabs.firstIndex(where: { $0.id == id }) else { return }
            let closed = space.tabs.remove(at: i)
            space.recentlyClosed = Array(((space.recentlyClosed ?? []) + [closed]).suffix(Self.recentlyClosedLimit))
            if space.selectedTabID == id {
                space.selectedTabID = otherPane ?? (space.tabs.indices.contains(i) ? space.tabs[i].id : space.tabs.last?.id)
            }
        }
        removeFromSplit(id)
    }

    /// Reopens a tab from the Library and takes it off the recently closed list.
    func reopenClosedTab(_ id: BrowserTab.ID) {
        guard let tab = selectedSpace?.recentlyClosed?.first(where: { $0.id == id }) else { return }
        mutateSelectedSpace { $0.recentlyClosed?.removeAll { $0.id == id } }
        openTab(tab.url, title: tab.title)
    }


    func updateTab(_ id: BrowserTab.ID, title: String?, url: URL?) {
        for s in spaces.indices where spaces[s].pageTab(id) != nil {
            spaces[s].updatePage(id, title: title, url: url)
        }
    }

    // MARK: Favorites

    /// Pins the tab: it moves into the favorites, page and all.
    func addFavorite(from tab: BrowserTab) {
        pinTab(tab.id, at: nil)
    }

    /// Removes a favorite. Returns its page's tab id, if it had one, so the page can be closed.
    @discardableResult
    func removeFavorite(_ id: Favorite.ID) -> BrowserTab.ID? {
        var page: BrowserTab.ID?
        mutateSelectedSpace { space in
            page = space.favorites.first { $0.id == id }?.tab?.id
            space.favorites.removeAll { $0.id == id }
            if let page, space.selectedTabID == page { space.selectedTabID = space.tabs.first?.id }
        }
        return page
    }

    /// Shows the favorite's own page (made on first use). The tab list is left alone.
    func selectFavorite(_ id: Favorite.ID) {
        mutateSelectedSpace { $0.selectFavorite(id) }
    }

    // MARK: Folders

    /// Adds a folder (in `parent`, holding `tabIDs`) and starts renaming it.
    func addFolder(in parent: Folder.ID? = nil, tabs tabIDs: [BrowserTab.ID] = []) {
        var added: Folder.ID?
        mutateSelectedSpace { space in
            added = space.addFolder(in: parent, tabs: tabIDs)
            if let parent, added != nil { space.setExpanded(parent, true) }
        }
        renamingFolderID = added
    }

    func renameFolder(_ id: Folder.ID, to name: String) {
        mutateSelectedSpace { $0.renameFolder(id, to: name) }
    }

    func setFolderExpanded(_ id: Folder.ID, _ expanded: Bool) {
        mutateSelectedSpace { $0.setExpanded(id, expanded) }
    }

    func setFoldersExpanded(_ expanded: Bool, under id: Folder.ID?) {
        mutateSelectedSpace { $0.setExpandedAll(expanded, under: id) }
    }

    func moveFolder(_ id: Folder.ID, to parent: Folder.ID?, before sibling: Folder.ID? = nil) {
        mutateSelectedSpace { $0.moveFolder(id, to: parent, before: sibling) }
    }

    func moveTabs(_ ids: [BrowserTab.ID], toFolder folder: Folder.ID?, before anchor: BrowserTab.ID? = nil) {
        mutateSelectedSpace { $0.moveTabs(ids, to: folder, before: anchor) }
    }

    /// Returns the tabs closed, so their pages can be released.
    @discardableResult
    func deleteFolder(_ id: Folder.ID, closingTabs: Bool) -> [BrowserTab.ID] {
        var closed: [BrowserTab.ID] = []
        mutateSelectedSpace { closed = $0.deleteFolder(id, closingTabs: closingTabs) }
        return closed
    }

    /// Unloads every tab in the folder, keeping them in place. Returns those that were loaded.
    @discardableResult
    func unloadFolder(_ id: Folder.ID) -> [BrowserTab.ID] {
        var unloaded: [BrowserTab.ID] = []
        mutateSelectedSpace { space in
            unloaded = space.unloadTabs(under: id)
            if let selected = space.selectedTabID, unloaded.contains(selected) {
                space.selectedTabID = space.tabs.first { $0.isUnloaded != true }?.id
            }
        }
        return unloaded
    }

    // MARK: Split view

    func split(containing tabID: BrowserTab.ID?) -> Split? {
        guard let tabID else { return nil }
        return selectedSpace?.splits?.first { $0.tabIDs.contains(tabID) }
    }

    /// Shows `tabIDs` (2 to 4, in order) as one split, taking them out of any other split.
    func makeSplit(_ tabIDs: [BrowserTab.ID], isVertical: Bool = false) {
        let ids = Array(tabIDs.prefix(Split.maxPanes))
        guard ids.count >= 2 else { return }
        ids.forEach(removeFromSplit)
        mutateSelectedSpace { space in
            space.splits = (space.splits ?? []) + [Split(tabIDs: ids, isVertical: isVertical)]
            if !ids.contains(space.selectedTabID ?? UUID()) { space.selectedTabID = ids[0] }
        }
    }

    /// Adds a tab as a pane next to `target` (after it, or before it with `before`), making a
    /// split if `target` isn't in one. `isVertical` sets a new split's axis.
    func addToSplit(_ tabID: BrowserTab.ID, beside target: BrowserTab.ID, before: Bool = false, isVertical: Bool? = nil) {
        // Splits are made of the tab list's tabs, not favorites' pages.
        guard tabID != target, let tabs = selectedSpace?.tabs,
              tabs.contains(where: { $0.id == tabID }), tabs.contains(where: { $0.id == target }) else { return }
        if let split = split(containing: target), !split.tabIDs.contains(tabID), split.tabIDs.count >= Split.maxPanes { return }
        removeFromSplit(tabID)
        if let split = split(containing: target) {
            mutateSplit(split.id) { split in
                let i = split.tabIDs.firstIndex(of: target)! + (before ? 0 : 1)
                split.tabIDs.insert(tabID, at: i)
                if let isVertical, split.tabIDs.count == 2 { split.isVertical = isVertical }
                split.evenOut()
            }
        } else {
            makeSplit(before ? [tabID, target] : [target, tabID], isVertical: isVertical ?? false)
        }
        selectTab(tabID)
    }

    /// Takes a tab out of its split; a split left with one pane goes back to a normal tab.
    func removeFromSplit(_ tabID: BrowserTab.ID) {
        mutateSelectedSpace { space in
            guard let i = space.splits?.firstIndex(where: { $0.tabIDs.contains(tabID) }) else { return }
            space.splits![i].tabIDs.removeAll { $0 == tabID }
            if space.splits![i].tabIDs.count < 2 {
                space.splits!.remove(at: i)
            } else {
                space.splits![i].evenOut()
            }
        }
    }

    /// Turns a split back into separate tabs.
    func dissolveSplit(_ id: Split.ID) {
        mutateSelectedSpace { $0.splits?.removeAll { $0.id == id } }
    }

    func setFractions(_ fractions: [Double], for splitID: Split.ID) {
        mutateSplit(splitID) { $0.fractions = fractions }
    }

    func evenOutSplit(_ splitID: Split.ID) {
        mutateSplit(splitID) { $0.evenOut() }
    }

    /// Moves a pane one place along its split, wrapping around.
    func movePane(_ tabID: BrowserTab.ID) {
        guard let split = split(containing: tabID) else { return }
        mutateSplit(split.id) { split in
            let i = split.tabIDs.firstIndex(of: tabID)!
            split.tabIDs.swapAt(i, (i + 1) % split.tabIDs.count)
        }
    }

    /// Moves focus to the previous or next pane of the current split.
    func focusPane(offset: Int) {
        guard let current = selectedTab?.id, let split = split(containing: current),
              let i = split.tabIDs.firstIndex(of: current) else { return }
        selectTab(split.tabIDs[(i + offset + split.tabIDs.count) % split.tabIDs.count])
    }

    /// ⌃Tab and ⌃⇧Tab: the next or previous open tab in the tab list, wrapping around.
    func selectTab(offset: Int) {
        guard let space = selectedSpace else { return }
        let open = space.tabs.filter { $0.isUnloaded != true }
        guard !open.isEmpty else { return }
        let i = open.firstIndex { $0.id == space.selectedTabID } ?? (offset > 0 ? -1 : 0)
        selectTab(open[(i + offset + open.count) % open.count].id)
    }

    /// ⌘1 to ⌘8 pick that tab in the list; ⌘9 picks the last one, as in Chrome.
    func selectTab(number: Int) {
        guard let tabs = selectedSpace?.tabs, !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) { selectTab(tabs[index].id) }
    }

    /// ⌘⇧T: the tab closed most recently in this space.
    func reopenLastClosedTab() {
        if let last = selectedSpace?.recentlyClosed?.last { reopenClosedTab(last.id) }
    }

    /// New Split: the next tab picked in the command bar opens beside the current one.
    func startNewSplit() {
        guard let current = selectedTab?.id else { isCommandBarOpen = true; return }
        if let split = split(containing: current), split.tabIDs.count >= Split.maxPanes { return }
        pendingSplitTabID = current
        isCommandBarOpen = true
    }

    private func mutateSplit(_ id: Split.ID, _ body: (inout Split) -> Void) {
        mutateSelectedSpace { space in
            guard let i = space.splits?.firstIndex(where: { $0.id == id }) else { return }
            body(&space.splits![i])
        }
    }

    // MARK: Dragging between tabs and favorites

    /// Pins a tab as a favorite before `index` (or at the end). The tab itself moves, so its
    /// page carries on without reloading.
    func pinTab(_ id: BrowserTab.ID, at index: Int?) {
        mutateSelectedSpace { $0.pinTab(id, at: index) }
    }

    /// Unpins a favorite: it goes back to the tab list as a tab, page and all, before `index`.
    @discardableResult
    func unpinFavorite(_ id: Favorite.ID, toTabAt index: Int?) -> BrowserTab.ID? {
        var tabID: BrowserTab.ID?
        mutateSelectedSpace { tabID = $0.unpinFavorite(id, toTabAt: index) }
        return tabID
    }

    /// Unpins a favorite into a folder (nil for loose tabs), before `anchor` or last.
    func unpinFavorite(_ id: Favorite.ID, toFolder folder: Folder.ID?, before anchor: BrowserTab.ID?) {
        guard let tabID = unpinFavorite(id, toTabAt: nil) else { return }
        moveTabs([tabID], toFolder: folder, before: anchor)
    }

    func moveFavorite(_ id: Favorite.ID, before index: Int?) {
        mutateSelectedSpace { Self.move(id, before: index, in: &$0.favorites) }
    }

    func moveTab(_ id: BrowserTab.ID, before index: Int?) {
        mutateSelectedSpace { Self.move(id, before: index, in: &$0.tabs) }
    }

    /// Moves tabs together, in their order, before the tab now at `index` (or to the end).
    func moveTabs(_ ids: [BrowserTab.ID], before index: Int?) {
        mutateSelectedSpace { space in
            let anchor = index.flatMap { i in space.tabs[i...].first { !ids.contains($0.id) }?.id }
            let moving = ids.compactMap { id in space.tabs.first { $0.id == id } }
            space.tabs.removeAll { ids.contains($0.id) }
            let at = anchor.flatMap { id in space.tabs.firstIndex { $0.id == id } } ?? space.tabs.count
            space.tabs.insert(contentsOf: moving, at: at)
        }
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
    func addSpace(name: String, theme: SpaceTheme, icon: String?, profileID: Profile.ID? = nil) {
        var profileID = profileID
        if profileID == nil {
            profileID = addProfile(name: name).id
        }
        let space = Space(name: name, theme: theme, icon: icon, profileID: profileID!)
        spaces.append(space)
        selectedSpaceID = space.id
    }

    /// A preset no space uses yet, so a new space stands apart; the first preset if all are used.
    func suggestedTheme() -> SpaceTheme {
        let used = Set(spaces.map(\.resolvedTheme.colors))
        return (ThemePreset.all.first { !used.contains($0.theme.colors) } ?? ThemePreset.all[0]).theme
    }

    func updateSpace(_ id: Space.ID, _ body: (inout Space) -> Void) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        body(&spaces[i])
    }

    func setIcon(_ icon: String?, for id: Space.ID) {
        updateSpace(id) { $0.icon = icon }
    }

    /// Moves a space to another profile. Returns its open pages, which belong to the old
    /// profile's logins and must be closed so they reload under the new one.
    func setProfile(_ profileID: Profile.ID, for id: Space.ID) -> [BrowserTab.ID] {
        guard let space = spaces.first(where: { $0.id == id }), space.profileID != profileID,
              profiles.contains(where: { $0.id == profileID }) else { return [] }
        updateSpace(id) { $0.profileID = profileID }
        return space.pageIDs
    }

    /// Deletes a space; the last one stays. Its profile is kept. Returns its pages to close.
    @discardableResult
    func deleteSpace(_ id: Space.ID) -> [BrowserTab.ID] {
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = spaces.remove(at: i)
        if selectedSpaceID == id { selectedSpaceID = spaces[max(i - 1, 0)].id }
        return removed.pageIDs
    }

    // MARK: Profiles

    func spaces(using profileID: Profile.ID) -> [Space] {
        spaces.filter { $0.profileID == profileID }
    }

    /// Adds a profile in the first badge color no other profile has.
    @discardableResult
    func addProfile(name: String) -> Profile {
        let used = Set(profiles.compactMap(\.tint))
        let profile = Profile(name: name, tint: SpaceTint.allCases.first { !used.contains($0) } ?? .blue)
        profiles.append(profile)
        return profile
    }

    func updateProfile(_ id: Profile.ID, _ body: (inout Profile) -> Void) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        body(&profiles[i])
    }

    /// Deletes a profile no space uses. Returns it so its data can be removed from disk.
    func deleteProfile(_ id: Profile.ID) -> Profile? {
        guard spaces(using: id).isEmpty, let i = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return profiles.remove(at: i)
    }

    // MARK: Extensions

    /// Pins an extension to the profile's extensions popover, after the ones already pinned,
    /// or unpins it.
    func setExtension(_ id: String, pinned: Bool, in profileID: Profile.ID) {
        guard let i = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var ids = profiles[i].pinnedExtensionIDs ?? []
        ids.removeAll { $0 == id }
        if pinned { ids.append(id) }
        profiles[i].pinnedExtensionIDs = ids
    }

    // MARK: Helpers

    private func mutateSelectedSpace(_ body: (inout Space) -> Void) {
        guard let i = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        body(&spaces[i])
    }
}
