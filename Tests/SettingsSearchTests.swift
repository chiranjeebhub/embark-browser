import Testing

/// The Settings sidebar's search.
struct SettingsSearchTests {
    @Test func findsASettingByWhatItDoes() {
        let titles = SettingsSearch.matches("little").map(\.title)
        #expect(titles == ["Open links in Little windows"])
        #expect(SettingsSearch.matches("duckduckgo").first?.pane == .general)
    }

    @Test func everyWordHasToMatch() {
        #expect(SettingsSearch.matches("cookies third").map(\.title) == ["Block third-party cookies"])
        #expect(SettingsSearch.matches("cookies zebra").isEmpty)
    }

    @Test func anEmptySearchFindsNothing() {
        #expect(SettingsSearch.matches("  ").isEmpty)
    }

    @Test func everyPageHasARowInTheIndex() {
        let indexed = Set(SettingsSearch.index.map(\.pane))
        #expect(indexed == Set(SettingsPane.allCases))
    }
}
