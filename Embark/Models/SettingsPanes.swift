import SwiftUI

extension PreferenceKey {
    /// The Settings page that was open last, so ⌘, comes back to it.
    static let settingsPane = "settingsPane"
}

/// One page of Settings. To add a page, add a case here, its look below, and its view in
/// `SettingsView.page(_:)`; its rows go in `SettingsSearch.index` so search finds them.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, profiles, passwords, privacy, shortcuts, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .profiles: "Profiles"
        case .passwords: "Passwords"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        case .about: "About Embark"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Your default browser, search, tabs and links from other apps."
        case .appearance: "How the sidebar looks and where it sits."
        case .profiles: "Separate logins, cookies, history and extensions."
        case .passwords: "Logins saved in your Mac’s Keychain."
        case .privacy: "Cookies, sign-ins and what sites can use."
        case .shortcuts: "Everything you can do from the keyboard."
        case .updates: "New versions of Embark, checked for and installed by itself."
        case .about: "Open source, made for the Mac."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .profiles: "person.2.fill"
        case .passwords: "key.fill"
        case .privacy: "hand.raised.fill"
        case .shortcuts: "command"
        case .updates: "arrow.down"
        case .about: "sailboat.fill"
        }
    }

    /// The icon tile's gradient, top to bottom.
    var colors: [Color] {
        switch self {
        case .general: [Color(white: 0.62), Color(white: 0.42)]
        case .appearance: [Color(red: 1, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.32, blue: 0.95)]
        case .profiles: [Color(red: 0.3, green: 0.7, blue: 1), Color(red: 0.2, green: 0.42, blue: 0.95)]
        case .passwords: [Color(red: 0.55, green: 0.6, blue: 0.68), Color(red: 0.32, green: 0.36, blue: 0.44)]
        case .privacy: [Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.25, green: 0.3, blue: 0.85)]
        case .shortcuts: [Color(red: 0.42, green: 0.42, blue: 0.48), Color(red: 0.2, green: 0.2, blue: 0.26)]
        case .updates: [Color(red: 0.35, green: 0.85, blue: 0.5), Color(red: 0.15, green: 0.62, blue: 0.35)]
        case .about: [Color(red: 0.44, green: 0.48, blue: 1), Color(red: 0.13, green: 0.7, blue: 0.65)]
        }
    }

    /// Shown in the sidebar after a gap, away from the pages you change things on.
    var isFooter: Bool { self == .updates || self == .about }
}

// MARK: - Search

/// Every row in Settings, so the sidebar's search can find a setting by what it does.
enum SettingsSearch {
    struct Item: Identifiable {
        let pane: SettingsPane
        /// The row's title, as `SettingRow` shows it, so the row can be lit up.
        let title: String
        var keywords = ""
        var id: String { "\(pane.rawValue) \(title)" }
    }

    static let index: [Item] = [
        Item(pane: .general, title: "Default browser", keywords: "links other apps make default"),
        Item(pane: .general, title: "Search engine", keywords: "google duckduckgo bing brave kagi ecosia perplexity command bar"),
        Item(pane: .general, title: "Archive tabs after", keywords: "auto archive close old tabs library clean up"),
        Item(pane: .general, title: "Open links in Little windows", keywords: "little arc air traffic popup small window links other apps"),
        Item(pane: .general, title: "Import bookmarks", keywords: "chrome brave edge safari html favorites"),
        Item(pane: .appearance, title: "Sidebar position", keywords: "left right side layout"),
        Item(pane: .appearance, title: "Show the address in the sidebar", keywords: "url pill address bar"),
        Item(pane: .appearance, title: "Show the sidebar at the window edge", keywords: "peek hover hidden auto hide"),
        Item(pane: .appearance, title: "New spaces start with", keywords: "theme color gradient space"),
        Item(pane: .profiles, title: "Profiles", keywords: "accounts logins separate work personal name color"),
        Item(pane: .profiles, title: "Extensions", keywords: "chrome web store add-ons plugins"),
        Item(pane: .profiles, title: "Browsing data", keywords: "clear cache cookies history storage"),
        Item(pane: .passwords, title: "Saved passwords", keywords: "logins keychain autofill import export csv"),
        Item(pane: .privacy, title: "Block third-party cookies", keywords: "tracking trackers privacy"),
        Item(pane: .privacy, title: "Start every session signed out", keywords: "clear cookies launch sign out"),
        Item(pane: .privacy, title: "Site permissions", keywords: "camera microphone notifications location sound allow block"),
        Item(pane: .shortcuts, title: "Keyboard shortcuts", keywords: "keys hotkeys command"),
        Item(pane: .updates, title: "Check for updates automatically", keywords: "update upgrade new version sparkle"),
        Item(pane: .updates, title: "Download and install updates automatically", keywords: "update auto install background"),
        Item(pane: .about, title: "Version", keywords: "about update license github source report problem"),
    ]

    static func matches(_ query: String) -> [Item] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return [] }
        return index.filter { item in
            let text = "\(item.title) \(item.pane.title) \(item.keywords)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}
