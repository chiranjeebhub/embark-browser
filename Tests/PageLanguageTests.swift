import Testing

/// Telling which language a page is in, and whether to offer translating it.
struct PageLanguageTests {
    @Test func detectsLanguageFromText() {
        let french = "Le gouvernement a annoncé mardi une série de mesures pour soutenir les familles et les entreprises."
        #expect(PageLanguage.detect(sample: french, declared: "en") == "fr")
    }

    @Test func fallsBackToDeclaredLanguageForShortText() {
        #expect(PageLanguage.detect(sample: "OK", declared: "de-DE") == "de")
        #expect(PageLanguage.detect(sample: "", declared: nil) == nil)
    }

    @Test func regionalVariantsAreNotForeign() {
        #expect(!PageLanguage.isForeign("en-GB", readerLanguages: ["en-US"]))
        #expect(PageLanguage.isForeign("fr", readerLanguages: ["en-US", "de"]))
        #expect(!PageLanguage.isForeign("de", readerLanguages: ["en-US", "de"]))
    }

    @Test func chineseScriptsAreDifferentLanguages() {
        #expect(PageLanguage.isForeign("zh-Hant", readerLanguages: ["zh-Hans-CN"]))
        #expect(!PageLanguage.isForeign("zh", readerLanguages: ["zh-Hans-CN"]))
        #expect(PageLanguage.key("zh-TW") == "zh-Hant")
    }
}
