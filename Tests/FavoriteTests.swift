import Foundation
import Testing

/// Favorites as their own tabs, and dropping tabs onto a folder.
struct FavoriteTests {
    private func space() -> Space {
        var space = Space(name: "Test", tint: .blue, profileID: UUID())
        space.tabs = ["a", "b", "c"].map { BrowserTab(title: $0, url: URL(string: "https://\($0).com")!) }
        space.favorites = [Favorite(title: "Mail", url: URL(string: "https://mail.example.com")!)]
        space.selectedTabID = space.tabs[0].id
        return space
    }

    @Test func selectingAFavoriteShowsItsOwnPageWithoutMakingATab() throws {
        var space = space()
        let favorite = space.favorites[0].id
        let pageResult = space.selectFavorite(favorite)
        let page = try #require(pageResult)
        #expect(space.tabs.count == 3)
        #expect(space.selectedTabID == page)
        #expect(space.favorites[0].tab?.id == page)
        #expect(space.pageTab(page)?.url.host() == "mail.example.com")
        // The tab list has no selected tab.
        #expect(!space.tabs.contains { $0.id == space.selectedTabID })
        // Selecting it again reuses the same page.
        let result8 = space.selectFavorite(favorite)
        #expect(result8 == page)
        #expect(space.tabs.count == 3)
    }

    @Test func navigatingAFavoriteKeepsItsPinnedAddress() throws {
        var space = space()
        let pageResult = space.selectFavorite(space.favorites[0].id)
        let page = try #require(pageResult)
        space.updatePage(page, title: "Inbox (3)", url: URL(string: "https://mail.example.com/inbox"))
        #expect(space.favorites[0].tab?.url.path() == "/inbox")
        #expect(space.favorites[0].url.absoluteString == "https://mail.example.com")
    }

    @Test func pinningMovesTheTabItselfIntoTheFavorites() throws {
        var space = space()
        let tab = space.tabs[1]
        let folderResult = space.addFolder(tabs: [space.tabs[2].id])
        let folder = try #require(folderResult)
        space.moveTabs([tab.id], to: folder)
        space.splits = [Split(tabIDs: [tab.id, space.tabs[0].id])]
        space.selectedTabID = tab.id
        let result9 = space.pinTab(tab.id, at: 0)
        #expect(result9)
        #expect(!space.tabs.contains { $0.id == tab.id })
        #expect(space.favorites.first?.tab?.id == tab.id)
        #expect(space.favorites.first?.tab?.folderID == nil)
        #expect(space.splits?.isEmpty == true)
        // Still selected, now as the favorite: same page, no reload.
        #expect(space.selectedTabID == tab.id)
        #expect(space.favorite(withPage: tab.id) != nil)
    }

    @Test func unpinningMovesThePageBackAsATab() throws {
        var space = space()
        let pageResult = space.selectFavorite(space.favorites[0].id)
        let page = try #require(pageResult)
        let tabIDResult = space.unpinFavorite(space.favorites[0].id, toTabAt: 1)
        let tabID = try #require(tabIDResult)
        #expect(tabID == page)
        #expect(space.favorites.isEmpty)
        #expect(space.tabs.map(\.id)[1] == page)
    }

    @Test func closingAFavoritesPageUnloadsIt() throws {
        var space = space()
        let pageResult = space.selectFavorite(space.favorites[0].id)
        let page = try #require(pageResult)
        space.unloadFavoritePage(page)
        #expect(space.favorites[0].tab?.isUnloaded == true)
        #expect(space.selectedTabID == space.tabs.first?.id)
        space.selectFavorite(space.favorites[0].id)
        #expect(space.favorites[0].tab?.isUnloaded == nil)
    }

    /// Dropping on a folder row puts the tab last in that folder.
    @Test func droppingOnAFolderAddsTheTabAtTheEnd() throws {
        var space = space()
        let folderResult = space.addFolder(tabs: [space.tabs[0].id, space.tabs[1].id])
        let folder = try #require(folderResult)
        let c = try #require(space.tabs.first { $0.title == "c" })
        space.moveTabs([c.id], to: folder, before: nil)
        #expect(space.tabs(in: folder).map(\.title) == ["a", "b", "c"])
        #expect(space.tabs(in: nil).isEmpty)
    }

    @Test func favoritesSavedBeforePagesStillLoad() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"Old","url":"https://old.example.com"}"#
        let favorite = try JSONDecoder().decode(Favorite.self, from: Data(json.utf8))
        #expect(favorite.tab == nil)
    }
}
