import Foundation
import Testing

/// Which space gets a link opened from another app.
struct LinkRoutingTests {
    private let profile = UUID()

    private func url(_ string: String) -> URL { URL(string: string)! }

    private func space(_ name: String, favorites: [String] = [], folderTabs: [String] = [], tabs: [String] = []) -> Space {
        var space = Space(name: name, profileID: profile)
        space.favorites = favorites.map { Favorite(title: $0, url: url($0)) }
        let folder = UUID()
        space.tabs = folderTabs.map { BrowserTab(title: $0, url: url($0), folderID: folder) }
            + tabs.map { BrowserTab(title: $0, url: url($0)) }
        return space
    }

    @Test func aFavoriteOnTheSameSiteWins() {
        let personal = space("Personal", favorites: ["https://www.youtube.com"])
        let work = space("Work", favorites: ["https://github.com"])
        #expect(LinkRouting.space(for: url("https://github.com/apple/swift/pull/1"), in: [personal, work]) == work.id)
        #expect(LinkRouting.space(for: url("https://youtube.com/watch?v=1"), in: [personal, work]) == personal.id)
    }

    @Test func subdomainsMatchButLookalikesDont() {
        let work = space("Work", favorites: ["https://google.com"])
        #expect(LinkRouting.space(for: url("https://mail.google.com/x"), in: [work]) == work.id)
        #expect(LinkRouting.space(for: url("https://notgoogle.com"), in: [work]) == nil)
    }

    @Test func folderTabsCountButLooseTabsDont() {
        let a = space("A", tabs: ["https://linear.app"])
        let b = space("B", folderTabs: ["https://linear.app/team"])
        #expect(LinkRouting.space(for: url("https://linear.app/issue/1"), in: [a, b]) == b.id)
        #expect(LinkRouting.space(for: url("https://figma.com"), in: [a, b]) == nil)
    }

    @Test func favoritesComeBeforeFolders() {
        let a = space("A", folderTabs: ["https://notion.so"])
        let b = space("B", favorites: ["https://notion.so"])
        #expect(LinkRouting.space(for: url("https://notion.so/page"), in: [a, b]) == b.id)
    }
}
