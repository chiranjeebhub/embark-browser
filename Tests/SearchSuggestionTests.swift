import Foundation
import Testing

/// Reading OpenSearch suggestion responses.
struct SearchSuggestionTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func readsTheSecondElement() {
        let response = data(#"["swift", ["swift ui", "swift concurrency", "taylor swift"]]"#)
        #expect(SearchSuggestions.parse(response, query: "swift") == ["swift ui", "swift concurrency", "taylor swift"])
    }

    @Test func dropsTheQueryRepeatsAndBlanks() {
        let response = data(#"["Swift", ["swift", "Swift UI", "swift ui", " ", 3, "xcode"]]"#)
        #expect(SearchSuggestions.parse(response, query: "Swift ") == ["Swift UI", "xcode"])
    }

    @Test func keepsToTheLimit() {
        let response = data(#"["a", ["a1", "a2", "a3", "a4", "a5"]]"#)
        #expect(SearchSuggestions.parse(response, query: "a", limit: 2) == ["a1", "a2"])
    }

    @Test func ignoresOtherShapes() {
        #expect(SearchSuggestions.parse(data(#"{"q": "a"}"#), query: "a").isEmpty)
        #expect(SearchSuggestions.parse(data("not json"), query: "a").isEmpty)
    }

    @Test func enginesWithoutAnEndpointGetNoURL() {
        #expect(SearchEngine.kagi.suggestionsURL(for: "a") == nil)
        let google = SearchEngine.google.suggestionsURL(for: "a b")
        #expect(google?.absoluteString.contains("q=a%20b") == true)
        #expect(SearchEngine.bing.suggestionsURL(for: "x")?.query()?.contains("query=x") == true)
    }
}
