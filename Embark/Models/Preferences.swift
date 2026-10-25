import Foundation

/// Settings window choices, kept in UserDefaults under these keys (views read them with
/// @AppStorage).
enum PreferenceKey {
    static let searchEngine = "searchEngine"
    static let archiveAfter = "archiveAfter"
    static let sidebarSide = "sidebarSide"
    static let showsAddressPill = "showsAddressPill"
    static let peeksAtEdge = "peeksAtEdge"
    static let newSpaceTheme = "newSpaceTheme"
    static let blocksThirdPartyCookies = "blocksThirdPartyCookies"
    static let signsOutAtLaunch = "signsOutAtLaunch"
}

/// Where the command bar sends a search.
enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, brave, kagi, ecosia, perplexity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .kagi: "Kagi"
        case .ecosia: "Ecosia"
        case .perplexity: "Perplexity"
        }
    }

    private var base: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .brave: "https://search.brave.com/search"
        case .kagi: "https://kagi.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        case .perplexity: "https://www.perplexity.ai/search"
        }
    }

    func url(searching query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func current(_ defaults: UserDefaults = .standard) -> SearchEngine {
        defaults.string(forKey: PreferenceKey.searchEngine).flatMap(SearchEngine.init) ?? .google
    }
}

/// How long a loose tab can go unopened before it moves to the Library, like Arc's archive.
enum ArchiveAfter: String, CaseIterable, Identifiable {
    case twelveHours, day, week, month, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twelveHours: "12 hours"
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .never: "Never"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .twelveHours: 12 * 3600
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        case .never: nil
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> ArchiveAfter {
        defaults.string(forKey: PreferenceKey.archiveAfter).flatMap(ArchiveAfter.init) ?? .day
    }
}

enum SidebarSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

/// The theme the Create a Space panel starts from.
enum NewSpaceTheme: String, CaseIterable, Identifiable {
    /// A preset no other space uses, so each space looks different.
    case unused
    /// The space that's open when the panel opens.
    case current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unused: "A theme no other space uses"
        case .current: "The current space’s theme"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> NewSpaceTheme {
        defaults.string(forKey: PreferenceKey.newSpaceTheme).flatMap(NewSpaceTheme.init) ?? .unused
    }
}

extension Space {
    /// Moves loose tabs not opened since `cutoff` to the recently closed list (newest kept
    /// up to `limit`), the way Arc archives them. Folder tabs, split panes and the selected tab
    /// stay, as do tabs in `keeping`. Returns the archived tabs, so their pages can be closed.
    @discardableResult
    mutating func archiveTabs(openedBefore cutoff: Date, keeping: Set<BrowserTab.ID> = [], limit: Int) -> [BrowserTab.ID] {
        let inSplits = Set((splits ?? []).flatMap(\.tabIDs))
        let archived = tabs.filter { tab in
            tab.folderID == nil && tab.lastActive < cutoff && tab.id != selectedTabID
                && !inSplits.contains(tab.id) && !keeping.contains(tab.id)
        }
        guard !archived.isEmpty else { return [] }
        let ids = Set(archived.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        // Oldest first, so the most recently used ends up newest in the Library.
        let ordered = archived.sorted { $0.lastActive < $1.lastActive }
        recentlyClosed = Array(((recentlyClosed ?? []) + ordered).suffix(limit))
        return archived.map(\.id)
    }
}
