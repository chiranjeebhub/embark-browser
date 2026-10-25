import Foundation
import Testing

/// Settings: search engines, archiving idle tabs, bookmark import and saved site permissions.
struct SettingsTests {
    private func tab(_ title: String, hoursAgo: Double, folder: Folder.ID? = nil) -> BrowserTab {
        BrowserTab(title: title, url: URL(string: "https://\(title).example")!,
                   lastActive: .now.addingTimeInterval(-hoursAgo * 3600), folderID: folder)
    }

    @Test func searchEnginesBuildQueries() throws {
        let url = try #require(SearchEngine.duckDuckGo.url(searching: "swift & ui"))
        #expect(url.host() == "duckduckgo.com")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "swift & ui")
        for engine in SearchEngine.allCases { #expect(engine.url(searching: "a b")?.scheme == "https") }
        let defaults = try #require(UserDefaults(suiteName: "SettingsTests"))
        defaults.removePersistentDomain(forName: "SettingsTests")
        #expect(SearchEngine.current(defaults) == .google)
        defaults.set("kagi", forKey: PreferenceKey.searchEngine)
        #expect(SearchEngine.current(defaults) == .kagi)
        #expect(ArchiveAfter.current(defaults) == .day)
        #expect(ArchiveAfter.never.interval == nil)
    }

    @Test func archivingKeepsFoldersSplitsAndTheSelectedTab() {
        var space = Space(name: "Work", profileID: UUID())
        let folder = space.addFolder()!
        let old = tab("old", hoursAgo: 48), older = tab("older", hoursAgo: 72), recent = tab("recent", hoursAgo: 1)
        let selected = tab("selected", hoursAgo: 99), inFolder = tab("folder", hoursAgo: 99, folder: folder)
        let paneA = tab("a", hoursAgo: 99), paneB = tab("b", hoursAgo: 99), kept = tab("kept", hoursAgo: 99)
        space.tabs = [old, older, recent, selected, inFolder, paneA, paneB, kept]
        space.selectedTabID = selected.id
        space.splits = [Split(tabIDs: [paneA.id, paneB.id])]

        let archived = space.archiveTabs(openedBefore: .now.addingTimeInterval(-24 * 3600), keeping: [kept.id], limit: 10)
        #expect(Set(archived) == [old.id, older.id])
        #expect(space.tabs.map(\.id) == [recent.id, selected.id, inFolder.id, paneA.id, paneB.id, kept.id])
        // The most recently used of them is newest in the Library.
        #expect(space.recentlyClosed?.map(\.id) == [older.id, old.id])
        #expect(space.archiveTabs(openedBefore: .now.addingTimeInterval(-24 * 3600), limit: 10).isEmpty)
    }

    @Test func archivingRespectsTheLimit() {
        var space = Space(name: "Home", profileID: UUID())
        space.tabs = (0..<5).map { tab("t\($0)", hoursAgo: Double(30 + $0)) }
        space.archiveTabs(openedBefore: .now.addingTimeInterval(-24 * 3600), limit: 3)
        #expect(space.tabs.isEmpty)
        #expect(space.recentlyClosed?.map(\.title) == ["t2", "t1", "t0"])
    }

    @Test func chromiumBookmarks() throws {
        let json = """
        {"roots": {
          "bookmark_bar": {"name": "Bookmarks bar", "type": "folder", "children": [
            {"type": "url", "name": "Swift", "url": "https://swift.org"},
            {"type": "url", "name": "Settings", "url": "chrome://settings"},
            {"type": "folder", "name": "Dev", "children": [{"type": "url", "name": "", "url": "https://github.com/x"}]},
            {"type": "folder", "name": "Empty", "children": []}]},
          "other": {"name": "Other bookmarks", "type": "folder", "children": []},
          "synced": {"name": "Mobile bookmarks", "type": "folder", "children": [{"type": "url", "name": "News", "url": "https://bbc.co.uk"}]}
        }}
        """
        let root = try BookmarkImport.chromium(Data(json.utf8), name: "Chrome")
        #expect(root.name == "Chrome")
        #expect(root.folders.map(\.name) == ["Bookmarks bar", "Mobile bookmarks"])
        #expect(root.bookmarkCount == 3)
        #expect(root.folders[0].bookmarks.map(\.title) == ["Swift"])
        // An untitled bookmark takes its host's name.
        #expect(root.folders[0].folders.map(\.name) == ["Dev"])
        #expect(root.folders[0].folders[0].bookmarks[0].title == "github.com")
        #expect(throws: BookmarkImportError.self) { try BookmarkImport.chromium(Data("[]".utf8), name: "x") }
    }

    @Test func chromiumProfilesFollowTheBrowsersOrder() {
        let json = #"{"profile": {"profiles_order": ["Profile 2", "Default"], "info_cache": {"Default": {"name": "Personal"}, "Profile 2": {"name": "Work"}, "Profile 3": {"name": ""}}}}"#
        let profiles = BookmarkImport.chromiumProfiles(localState: Data(json.utf8))
        #expect(profiles.map(\.directory) == ["Profile 2", "Default", "Profile 3"])
        #expect(profiles.map(\.name) == ["Work", "Personal", "Profile 3"])
    }

    @Test func safariBookmarks() throws {
        let plist: [String: Any] = ["WebBookmarkType": "WebBookmarkTypeList", "Children": [
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com", "URIDictionary": ["title": "Apple"]],
            ]],
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://example.com/post", "URIDictionary": ["title": "Post"]],
            ]],
            ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let root = try BookmarkImport.safari(data)
        #expect(root.name == "Safari")
        #expect(root.folders.map(\.name) == ["Favorites", "Reading List"])
        #expect(root.bookmarkCount == 2)
    }

    @Test func exportedHTMLBookmarks() {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE><H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="1" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
            <DL><p>
                <DT><A HREF="https://swift.org/" ADD_DATE="1">Swift &amp; Friends</A>
                <DT><H3>Tools</H3>
                <DL><p>
                    <DT><A HREF="https://github.com">GitHub</A>
                    <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
                </DL><p>
            </DL><p>
            <DT><A HREF="https://news.ycombinator.com">HN</A>
        </DL><p>
        """
        let root = BookmarkImport.html(html, name: "Imported")
        #expect(root.bookmarks.map(\.title) == ["HN"])
        #expect(root.folders.map(\.name) == ["Bookmarks Bar"])
        #expect(root.folders[0].bookmarks.map(\.title) == ["Swift & Friends"])
        #expect(root.folders[0].folders.map(\.name) == ["Tools"])
        #expect(root.folders[0].folders[0].bookmarks.map(\.url.host) == ["github.com"])
        #expect(root.bookmarkCount == 3)
    }

    @Test func importAddsCollapsedFoldersOfUnloadedTabs() throws {
        // Five levels deep: the fifth level's bookmarks go into the fourth.
        var deepest = ImportedFolder(name: "L5", bookmarks: [ImportedBookmark(title: "deep", url: URL(string: "https://deep.example")!)])
        for level in (1...4).reversed() {
            deepest = ImportedFolder(name: "L\(level)", bookmarks: [ImportedBookmark(title: "b\(level)", url: URL(string: "https://b\(level).example")!)],
                                     folders: [deepest])
        }
        var space = Space(name: "Personal", profileID: UUID())
        space.tabs = [tab("existing", hoursAgo: 0)]
        #expect(space.importBookmarks(deepest) == 5)
        #expect(space.tabs.count == 6)
        #expect(space.allFolders.count == 4)
        #expect(space.allFolders.allSatisfy { !$0.isExpanded })
        let added = space.tabs.dropFirst()
        #expect(added.allSatisfy { $0.isUnloaded == true && $0.folderID != nil })
        let l4 = try #require(space.allFolders.first { $0.name == "L4" })
        #expect(space.depth(of: l4.id) == Folder.maxDepth)
        #expect(space.tabs(in: l4.id).map(\.title) == ["b4", "deep"])
        #expect(space.importBookmarks(ImportedFolder(name: "Nothing")) == 0)
    }

    @Test func siteExceptionsFromChromiumPreferences() {
        let json = """
        {"profile": {"content_settings": {"exceptions": {
          "media_stream_camera": {"https://meet.google.com:443,*": {"setting": 1}, "https://bad.example:443,*": {"setting": 2}},
          "notifications": {"https://app.slack.com:443,*": {"setting": 1}, "https://asked.example:443,*": {"setting": 3},
                            "https://old.example:443,*": {"last_modified": "1"}},
          "cookies": {"https://ignored.example:443,*": {"setting": 1}}
        }}}}
        """
        let exceptions = ChromiumPreferences.siteExceptions(Data(json.utf8), contentTypes: ["media_stream_camera", "notifications"])
        #expect(exceptions.map(\.host) == ["app.slack.com", "bad.example", "meet.google.com"])
        #expect(exceptions.map(\.isAllowed) == [true, false, true])
        #expect(exceptions[2].origin == "https://meet.google.com:443")
        #expect(ChromiumPreferences.siteExceptions(Data("{}".utf8), contentTypes: ["sound"]).isEmpty)
    }
}
