import Foundation
import NaturalLanguage

extension PreferenceKey {
    /// The language pages are translated into; unset means the first of the system's languages.
    static let translateTarget = "translateTarget"
    /// Languages whose pages are translated as soon as they load (Translate ▸ Always translate).
    static let autoTranslateLanguages = "autoTranslateLanguages"
}

/// Which language a page is written in, and whether to offer translating it.
enum PageLanguage {
    /// The language of a page's text, as a BCP 47 identifier like "fr" or "zh-Hant". Uses the
    /// text when there's enough of it, since sites often leave `lang` at a template's default.
    static func detect(sample: String, declared: String?) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if sample.count >= 40, let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= 0.6 {
            return normalized(best.key.rawValue)
        }
        guard let declared = declared?.trimmingCharacters(in: .whitespaces), !declared.isEmpty else { return nil }
        return normalized(declared)
    }

    /// The shortest identifier for a language, as Apple's Translation lists them ("zh" for
    /// Simplified Chinese, "zh-Hant" for Traditional).
    static func normalized(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).minimalIdentifier
    }

    /// Whether a page in `language` is in none of the languages the person reads.
    static func isForeign(_ language: String, readerLanguages: [String] = Locale.preferredLanguages) -> Bool {
        let page = key(language)
        return !readerLanguages.contains { key($0) == page }
    }

    /// Language, plus the script for Chinese, whose two scripts are read as different languages.
    static func key(_ identifier: String) -> String {
        let language = Locale.Language(identifier: identifier)
        let code = language.languageCode?.identifier ?? identifier.lowercased()
        guard code == "zh" else { return code }
        let script = language.script?.identifier ?? (["TW", "HK", "MO"].contains(language.region?.identifier ?? "") ? "Hant" : "Hans")
        return "zh-\(script)"
    }

    /// "French", "Chinese, Traditional" — in the person's own language.
    static func name(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)
            ?? Locale.current.localizedString(forLanguageCode: identifier)
            ?? identifier
    }

    /// The language pages are translated into.
    static var target: String {
        UserDefaults.standard.string(forKey: PreferenceKey.translateTarget)
            ?? Locale.preferredLanguages.first.map { Locale.Language(identifier: $0).minimalIdentifier }
            ?? "en"
    }

    static var autoTranslated: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: PreferenceKey.autoTranslateLanguages) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: PreferenceKey.autoTranslateLanguages) }
    }
}
