import Foundation
import Testing

/// The folder rules on `Space`: adding and nesting, the depth cap, moving tabs and folders,
/// deleting with or without the tabs, unloading, and loading state saved before folders.
struct FolderTests {
    private func space(tabs titles: [String] = ["a", "b", "c", "d"]) -> Space {
        var space = Space(name: "Test", tint: .blue, profileID: UUID())
        space.tabs = titles.map { BrowserTab(title: $0, url: URL(string: "https://\($0).com")!) }
        return space
    }

    private func id(_ space: Space, _ title: String) -> BrowserTab.ID { space.tabs.first { $0.title == title }!.id }
    private func titles(_ space: Space, in folder: Folder.ID?) -> [String] { space.tabs(in: folder).map(\.title) }

    @Test func addFolderWithTabsAndNest() throws {
        var space = space()
        let workID = space.addFolder(named: "Work", tabs: [id(space, "b"), id(space, "c")])
        let work = try #require(workID)
        #expect(titles(space, in: work) == ["b", "c"])
        #expect(titles(space, in: nil) == ["a", "d"])
        let subID = space.addFolder(named: "Sub", in: work)
        let sub = try #require(subID)
        #expect(space.subfolders(of: work).map(\.id) == [sub])
        #expect(space.depth(of: sub) == 2)
        #expect(space.height(of: work) == 2)
    }

    @Test func depthIsCapped() throws {
        var space = space()
        var parent: Folder.ID? = nil
        for _ in 1...Folder.maxDepth {
            let next = space.addFolder(in: parent)
            parent = try #require(next)
        }
        let result1 = space.addFolder(in: parent)
        #expect(result1 == nil)
        #expect(space.allFolders.count == Folder.maxDepth)
    }

    @Test func moveFolderRefusesCyclesAndTooDeep() throws {
        var space = space()
        let outerID = space.addFolder(named: "Outer")
        let outer = try #require(outerID)
        let innerID = space.addFolder(named: "Inner", in: outer)
        let inner = try #require(innerID)
        let result2 = space.moveFolder(outer, to: inner)
        #expect(!result2)
        let result3 = space.moveFolder(outer, to: outer)
        #expect(!result3)

        // A two-level folder fits under depth 2, not depth 3.
        let aID = space.addFolder(named: "A")
        let a = try #require(aID)
        let bID = space.addFolder(named: "B", in: a)
        let b = try #require(bID)
        let cID = space.addFolder(named: "C", in: b)
        let c = try #require(cID)
        let result4 = space.moveFolder(outer, to: c)
        #expect(!result4)
        let result5 = space.moveFolder(outer, to: b)
        #expect(result5)
        #expect(space.depth(of: inner) == 4)
    }

    @Test func moveFolderReorders() throws {
        var space = space()
        let oneID = space.addFolder(named: "1")
        let one = try #require(oneID)
        let twoID = space.addFolder(named: "2")
        let two = try #require(twoID)
        let threeID = space.addFolder(named: "3")
        let three = try #require(threeID)
        let result6 = space.moveFolder(three, to: nil, before: one)
        #expect(result6)
        #expect(space.subfolders(of: nil).map(\.id) == [three, one, two])
    }

    @Test func moveTabsIntoAndOutOfFolders() throws {
        var space = space()
        let folderID = space.addFolder(tabs: [id(space, "a")])
        let folder = try #require(folderID)
        space.moveTabs([id(space, "d")], to: folder, before: id(space, "a"))
        #expect(titles(space, in: folder) == ["d", "a"])
        space.moveTabs([id(space, "a")], to: nil, before: id(space, "b"))
        #expect(titles(space, in: nil) == ["a", "b", "c"])
        #expect(titles(space, in: folder) == ["d"])
    }

    @Test func deleteKeepingTabsMovesThemToTheParent() throws {
        var space = space()
        let outerID = space.addFolder(named: "Outer", tabs: [id(space, "a")])
        let outer = try #require(outerID)
        let innerID = space.addFolder(named: "Inner", in: outer, tabs: [id(space, "b")])
        let inner = try #require(innerID)
        let closed = space.deleteFolder(inner, closingTabs: false)
        #expect(closed.isEmpty)
        #expect(titles(space, in: outer) == ["a", "b"])
        #expect(space.folder(inner) == nil)
    }

    @Test func deleteClosingTabsRemovesTheSubtreeAndItsSplits() throws {
        var space = space()
        let outerID = space.addFolder(named: "Outer", tabs: [id(space, "a")])
        let outer = try #require(outerID)
        let innerID = space.addFolder(named: "Inner", in: outer, tabs: [id(space, "b")])
        _ = try #require(innerID)
        space.splits = [Split(tabIDs: [id(space, "b"), id(space, "c")])]
        space.selectedTabID = id(space, "a")
        let closed = space.deleteFolder(outer, closingTabs: true)
        #expect(closed.count == 2)
        #expect(space.tabs.map(\.title) == ["c", "d"])
        #expect(space.allFolders.isEmpty)
        #expect(space.splits?.isEmpty == true)
        #expect(space.selectedTabID == space.tabs.first?.id)
    }

    @Test func unloadKeepsTabsInPlace() throws {
        var space = space()
        let folderID = space.addFolder(tabs: [id(space, "a"), id(space, "b")])
        let folder = try #require(folderID)
        let result7 = space.unloadTabs(under: folder)
        #expect(result7.count == 2)
        #expect(space.tabs(in: folder).allSatisfy { $0.isUnloaded == true })
        let result8 = space.unloadTabs(under: folder)
        #expect(result8.isEmpty)
    }

    @Test func expandAndCollapseAll() throws {
        var space = space()
        let outerID = space.addFolder()
        let outer = try #require(outerID)
        let innerID = space.addFolder(in: outer)
        let inner = try #require(innerID)
        space.setExpandedAll(false, under: outer)
        #expect(space.folder(outer)?.isExpanded == false && space.folder(inner)?.isExpanded == false)
        space.setExpanded(inner, true)
        #expect(space.folder(inner)?.isExpanded == true)
    }

    /// state.json written before folders (no `folders`, `folderID` or `isUnloaded`) still loads.
    @Test func loadsStateSavedBeforeFolders() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","tint":"purple","profileID":"\(UUID().uuidString)",
         "favorites":[],"tabs":[{"id":"\(UUID().uuidString)","title":"x","url":"https://x.com","lastActive":0}]}
        """
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        #expect(space.allFolders.isEmpty)
        #expect(space.tabs.first?.folderID == nil)
        #expect(space.tabs.first?.isUnloaded == nil)
        #expect(titles(space, in: nil) == ["x"])
    }
}

/// Folder names cleaned of drag tokens, and the drag session clearing.
struct FolderNameAndDragTests {
    @Test func cleansDragTokensFromSavedNames() throws {
        var space = Space(name: "Test", tint: .blue, profileID: UUID())
        space.folders = [
            Folder(name: "Untitled Foldeembark-tab:EB12AB34-56CD"),
            Folder(name: "embark-tab:\(UUID().uuidString)"),
            Folder(name: "  Work  "),
        ]
        space.cleanFolderNames()
        #expect(space.allFolders.map(\.name) == ["Untitled Folde", "Untitled Folder", "Work"])
    }

    @Test func renameIgnoresDragTokens() throws {
        var space = Space(name: "Test", tint: .blue, profileID: UUID())
        let added = space.addFolder()
        let id = try #require(added)
        space.renameFolder(id, to: "Trips embark-folder:\(UUID().uuidString)")
        #expect(space.folder(id)?.name == "Trips")
        space.renameFolder(id, to: "embark-tab:ABCD")
        #expect(space.folder(id)?.name == "Trips")
    }

    @Test func dragSessionClearsOnFinishAndOnTheNextStart() {
        var session = DragSession()
        session.begin("embark-tab:\(UUID().uuidString)")
        #expect(session.isActive)
        let started = session.changes
        session.finish()
        #expect(!session.isActive)
        #expect(session.changes == started + 1)
        session.finish()
        #expect(!session.isActive)
        session.begin("embark-folder:\(UUID().uuidString)")
        #expect(session.isActive && session.changes == started + 3)
    }
}
