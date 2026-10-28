import Testing

/// Reader mode's article page and its style.
struct ReaderTests {
    private func article(_ text: String, title: String? = "A <b>bold</b> title") -> ReaderArticle {
        ReaderArticle(title: title, byline: "Ada & co", siteName: nil, content: "<p>\(text)</p>", textContent: text)
    }

    @Test func readingTimeCountsWords() {
        let words = Array(repeating: "word", count: 690).joined(separator: " ")
        #expect(article(words).minutesToRead == 3)
        #expect(article("short").minutesToRead == 1)
    }

    @Test func readingTimeCountsCharactersWithoutSpaces() {
        let text = String(repeating: "読", count: 1500)
        #expect(article(text).minutesToRead == 3)
    }

    @Test func titleAndBylineAreEscaped() {
        let html = ReaderPage.html(article("Hello"), style: ReaderStyle(), sourceHost: "example.com")
        #expect(html.contains("A &lt;b&gt;bold&lt;/b&gt; title"))
        #expect(html.contains("Ada &amp; co"))
        #expect(html.contains("<p class=\"site\">example.com</p>"))
        #expect(html.contains("<p>Hello</p>"))
    }

    @Test func fontSizeStepsStayInRange() {
        var style = ReaderStyle()
        #expect(style.fontSize(steppedBy: 1) == 21)
        #expect(style.fontSize(steppedBy: -1) == 18)
        style.fontSize = ReaderStyle.fontSizes.last!
        #expect(style.fontSize(steppedBy: 1) == ReaderStyle.fontSizes.last!)
        style.fontSize = 20
        #expect(style.fontSize(steppedBy: 1) == 23)
    }

    @Test func shortPagesAreNotArticles() {
        #expect(!article("Too short").isUsable)
        #expect(article(String(repeating: "Long enough text. ", count: 10)).isUsable)
    }
}
