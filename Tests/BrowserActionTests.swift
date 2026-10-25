import Testing

/// Finding actions by typing in the ⌘T bar.
struct BrowserActionTests {
    @Test func typingTheStartOfANameFindsIt() {
        #expect(BrowserAction.matching("new win").first == .newWindow)
        #expect(BrowserAction.matching("copy").first == .copyURL)
    }

    @Test func keywordsFindActionsToo() {
        #expect(BrowserAction.matching("incognito") == [.newPrivateWindow])
        #expect(BrowserAction.matching("inspect").contains(.developerTools))
    }

    @Test func everyWordHasToMatch() {
        #expect(BrowserAction.matching("new banana").isEmpty)
    }

    @Test func oneLetterShowsNothing() {
        #expect(BrowserAction.matching("n").isEmpty)
    }
}
