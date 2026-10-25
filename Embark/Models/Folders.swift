import Foundation

/// A folder in a space's tab list, as in Arc. Folders nest; tabs belong to one through
/// `BrowserTab.folderID`. Siblings keep the order they have in `Space.folders`.
struct Folder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var parentID: Folder.ID?
    var isExpanded = true

    /// Folders nest at most this deep, counting the top level as 1.
    static let maxDepth = 4
    static let defaultName = "Untitled Folder"

    /// Removes sidebar drag tokens ("embark-tab:<id>", whole or cut short) from text. A drag
    /// dropped into a name field once inserted one.
    static func strippingDragTokens(_ text: String) -> String {
        text.replacing(/embark-(tab|favorite|split|folder):[0-9A-Fa-f-]*/, with: "")
    }

    /// A folder name without drag tokens or surrounding spaces; "Untitled Folder" if nothing's left.
    static func cleanName(_ name: String) -> String {
        let name = strippingDragTokens(name).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultName : name
    }
}

/// Folder rules, kept on `Space` so they can be tested without the store.
extension Space {
    var allFolders: [Folder] { folders ?? [] }

    func folder(_ id: Folder.ID) -> Folder? { allFolders.first { $0.id == id } }

    /// Subfolders of `parent` (nil for the top level), in order.
    func subfolders(of parent: Folder.ID?) -> [Folder] { allFolders.filter { $0.parentID == parent } }

    /// Tabs directly in `folder` (nil for loose tabs), in order.
    func tabs(in folder: Folder.ID?) -> [BrowserTab] { tabs.filter { $0.folderID == folder } }

    /// 1 for a top-level folder.
    func depth(of id: Folder.ID) -> Int {
        var depth = 0, current: Folder.ID? = id
        while let id = current, let folder = folder(id) { depth += 1; current = folder.parentID }
        return depth
    }

    /// Levels in the folder's subtree, counting itself: 1 with no subfolders.
    func height(of id: Folder.ID) -> Int {
        1 + (subfolders(of: id).map { height(of: $0.id) }.max() ?? 0)
    }

    /// The folder and everything inside it.
    func folderAndDescendants(_ id: Folder.ID) -> [Folder.ID] {
        [id] + subfolders(of: id).flatMap { folderAndDescendants($0.id) }
    }

    /// Every tab in the folder or its subfolders.
    func tabIDs(under id: Folder.ID) -> [BrowserTab.ID] {
        let folders = Set(folderAndDescendants(id))
        return tabs.filter { $0.folderID.map(folders.contains) ?? false }.map(\.id)
    }

    /// Adds a folder at the end of `parent`'s folders, moving `tabIDs` into it. Nil when it
    /// would nest deeper than `Folder.maxDepth`.
    @discardableResult
    mutating func addFolder(named name: String = Folder.defaultName, in parent: Folder.ID? = nil,
                            tabs tabIDs: [BrowserTab.ID] = []) -> Folder.ID? {
        if let parent, depth(of: parent) >= Folder.maxDepth { return nil }
        let folder = Folder(name: name, parentID: parent)
        folders = allFolders + [folder]
        if !tabIDs.isEmpty { moveTabs(tabIDs, to: folder.id) }
        return folder.id
    }

    mutating func renameFolder(_ id: Folder.ID, to name: String) {
        let name = Folder.strippingDragTokens(name).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = folders?.firstIndex(where: { $0.id == id }) else { return }
        folders![i].name = name
    }

    /// Cleans every folder name; used on saved state, which may hold names from before
    /// drag tokens were kept out.
    mutating func cleanFolderNames() {
        folders = folders?.map { folder in
            var folder = folder
            folder.name = Folder.cleanName(folder.name)
            return folder
        }
    }

    mutating func setExpanded(_ id: Folder.ID, _ expanded: Bool) {
        guard let i = folders?.firstIndex(where: { $0.id == id }) else { return }
        folders![i].isExpanded = expanded
    }

    /// Expands or collapses `id` and everything in it, or every folder when `id` is nil.
    mutating func setExpandedAll(_ expanded: Bool, under id: Folder.ID? = nil) {
        let ids = Set(id.map(folderAndDescendants) ?? allFolders.map(\.id))
        folders = allFolders.map { folder in
            var folder = folder
            if ids.contains(folder.id) { folder.isExpanded = expanded }
            return folder
        }
    }

    /// Moves a folder into `parent` (nil for the top level), before `sibling` or last.
    /// Refused if it would go inside itself or nest deeper than `Folder.maxDepth`.
    @discardableResult
    mutating func moveFolder(_ id: Folder.ID, to parent: Folder.ID?, before sibling: Folder.ID? = nil) -> Bool {
        guard var folder = folder(id) else { return false }
        if let parent {
            guard !folderAndDescendants(id).contains(parent),
                  depth(of: parent) + height(of: id) <= Folder.maxDepth else { return false }
        }
        var folders = allFolders
        folders.removeAll { $0.id == id }
        folder.parentID = parent
        let index = sibling.flatMap { s in folders.firstIndex { $0.id == s } }
            ?? folders.lastIndex { $0.parentID == parent }.map { $0 + 1 }
            ?? folders.count
        folders.insert(folder, at: index)
        self.folders = folders
        return true
    }

    /// Puts tabs into `folder` (nil for loose tabs), in their order, before `anchor` or after
    /// the folder's last tab.
    mutating func moveTabs(_ ids: [BrowserTab.ID], to folder: Folder.ID?, before anchor: BrowserTab.ID? = nil) {
        var moving = ids.compactMap { id in tabs.first { $0.id == id } }
        guard !moving.isEmpty else { return }
        for i in moving.indices { moving[i].folderID = folder }
        tabs.removeAll { ids.contains($0.id) }
        let index = anchor.flatMap { a in tabs.firstIndex { $0.id == a } }
            ?? tabs.lastIndex { $0.folderID == folder }.map { $0 + 1 }
            ?? tabs.count
        tabs.insert(contentsOf: moving, at: index)
    }

    /// Deletes a folder and its subfolders. Their tabs are closed (and returned, so their pages
    /// can be released) or kept by moving them to the folder's parent.
    @discardableResult
    mutating func deleteFolder(_ id: Folder.ID, closingTabs: Bool) -> [BrowserTab.ID] {
        guard let folder = folder(id) else { return [] }
        let removed = Set(folderAndDescendants(id))
        let tabIDs = tabIDs(under: id)
        folders = allFolders.filter { !removed.contains($0.id) }
        if closingTabs {
            tabs.removeAll { tabIDs.contains($0.id) }
            splits = splits?.compactMap { split in
                var split = split
                split.tabIDs.removeAll { tabIDs.contains($0) }
                guard split.tabIDs.count >= 2 else { return nil }
                split.evenOut()
                return split
            }
            if let selected = selectedTabID, tabIDs.contains(selected) { selectedTabID = tabs.first?.id }
            return tabIDs
        }
        for i in tabs.indices where tabs[i].folderID.map(removed.contains) ?? false {
            tabs[i].folderID = folder.parentID
        }
        return []
    }

    /// Marks a folder's tabs (and its subfolders') unloaded, returning those that were loaded.
    @discardableResult
    mutating func unloadTabs(under id: Folder.ID) -> [BrowserTab.ID] {
        let ids = Set(tabIDs(under: id))
        var unloaded: [BrowserTab.ID] = []
        for i in tabs.indices where ids.contains(tabs[i].id) && tabs[i].isUnloaded != true {
            tabs[i].isUnloaded = true
            unloaded.append(tabs[i].id)
        }
        return unloaded
    }
}
