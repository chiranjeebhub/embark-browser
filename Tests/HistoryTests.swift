import Foundation
import Testing

/// Recording visits, searching them, and clearing them.
struct HistoryTests {
    private let work = UUID()
    private let home = UUID()

    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func repeatVisitsShareOneEntryAndMoveToTheTop() {
        var history = History()
        history.recordVisit(to: url("https://a.com"), title: "A", profileID: work)
        history.recordVisit(to: url("https://b.com"), title: "B", profileID: work)
        history.recordVisit(to: url("https://a.com"), title: "A again", profileID: work)
        #expect(history.entries.map(\.title) == ["A again", "B"])
        #expect(history.entries[0].visitCount == 2)
    }

    @Test func profilesKeepSeparateEntries() {
        var history = History()
        history.recordVisit(to: url("https://a.com"), title: "A", profileID: work)
        history.recordVisit(to: url("https://a.com"), title: "A", profileID: home)
        #expect(history.entries.count == 2)
        #expect(history.search("a", profileID: home).count == 1)
    }

    @Test func onlyWebPagesAreRecorded() {
        var history = History()
        history.recordVisit(to: url("about:blank"), title: nil, profileID: work)
        history.recordVisit(to: url("chrome-extension://abc/popup.html"), title: "Popup", profileID: work)
        #expect(history.entries.isEmpty)
    }

    @Test func aMissingTitleFallsBackToTheHostUntilItArrives() {
        var history = History()
        history.recordVisit(to: url("https://news.example.com/x"), title: nil, profileID: work)
        #expect(history.entries[0].title == "news.example.com")
        history.updateTitle("Headlines", for: url("https://news.example.com/x"), profileID: work)
        #expect(history.entries[0].title == "Headlines")
        #expect(history.entries[0].visitCount == 1)
    }

    @Test func searchNeedsEveryWordAndRanksHostMatchesFirst() {
        var history = History()
        let now = Date.now
        history.recordVisit(to: url("https://blog.example.com/github-tips"), title: "Tips for github", profileID: work, at: now)
        history.recordVisit(to: url("https://github.com/apple/swift"), title: "apple/swift", profileID: work, at: now)
        let results = history.search("github", now: now)
        #expect(results.first?.url.host() == "github.com")
        #expect(history.search("github swift", now: now).count == 1)
        #expect(history.search("nothing", now: now).isEmpty)
    }

    @Test func clearingSinceADateKeepsOlderVisits() {
        var history = History()
        let now = Date.now
        history.recordVisit(to: url("https://old.com"), title: "Old", profileID: work, at: now.addingTimeInterval(-7200))
        history.recordVisit(to: url("https://new.com"), title: "New", profileID: work, at: now)
        history.clear(since: now.addingTimeInterval(-3600))
        #expect(history.entries.map(\.title) == ["Old"])
        history.clear()
        #expect(history.entries.isEmpty)
    }

    @Test func entriesGroupByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = Date(timeIntervalSince1970: 86_400 * 10 + 3600)
        let day2 = day1.addingTimeInterval(86_400)
        let entries = [
            HistoryEntry(url: url("https://a.com"), title: "A", profileID: work, lastVisited: day1),
            HistoryEntry(url: url("https://b.com"), title: "B", profileID: work, lastVisited: day2),
            HistoryEntry(url: url("https://c.com"), title: "C", profileID: work, lastVisited: day2.addingTimeInterval(60)),
        ]
        let groups = History.byDay(entries, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].entries.map(\.title) == ["C", "B"])
        #expect(groups[1].entries.map(\.title) == ["A"])
    }

    @Test func recentSitesShowEachSiteOnceNewestFirst() {
        var history = History()
        history.recordVisit(to: url("https://www.a.com/1"), title: "A1", profileID: work)
        history.recordVisit(to: url("https://b.com"), title: "B", profileID: work)
        history.recordVisit(to: url("https://c.com"), title: "C", profileID: home)
        history.recordVisit(to: url("https://a.com/2"), title: "A2", profileID: work)
        history.recordVisit(to: url("https://d.com"), title: "D", profileID: work)
        let recent = history.recentSites(profileID: work, excluding: ["d.com"])
        #expect(recent.map(\.title) == ["A2", "B"])
        #expect(history.recentSites(profileID: work, limit: 1).map(\.title) == ["D"])
    }

    @Test func topSitesAddUpVisitsPerSite() {
        var history = History()
        let now = Date.now
        for _ in 0..<3 { history.recordVisit(to: url("https://a.com/x"), title: "AX", profileID: work, at: now) }
        history.recordVisit(to: url("https://a.com/y"), title: "AY", profileID: work, at: now)
        for _ in 0..<3 { history.recordVisit(to: url("https://b.com"), title: "B", profileID: work, at: now) }
        // Visited often, but long ago.
        for _ in 0..<5 { history.recordVisit(to: url("https://old.com"), title: "Old", profileID: work, at: now.addingTimeInterval(-86_400 * 200)) }
        let top = history.topSites(profileID: work, now: now)
        #expect(top.map(\.title) == ["AX", "B", "Old"])
        #expect(history.topSites(profileID: work, excluding: ["a.com"], now: now).first?.title == "B")
    }
}
