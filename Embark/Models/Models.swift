import SwiftUI

/// A browsing profile: its own cookies, logins, cache and history on disk.
struct Profile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

/// A site pinned to a space's favorites grid.
struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
}

/// An open page in a space's tab list.
struct BrowserTab: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var lastActive = Date.now
}

/// A space groups favorites and tabs under one profile and one tint.
struct Space: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var tint: SpaceTint
    var profileID: Profile.ID
    var favorites: [Favorite] = []
    var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID?
}

enum SpaceTint: String, Codable, CaseIterable {
    case purple, blue, teal, orange, pink, graphite

    var color: Color {
        switch self {
        case .purple: Color(red: 0.54, green: 0.31, blue: 0.85)
        case .blue: Color(red: 0.04, green: 0.39, blue: 0.85)
        case .teal: Color(red: 0.06, green: 0.58, blue: 0.53)
        case .orange: Color(red: 0.91, green: 0.35, blue: 0.05)
        case .pink: Color(red: 0.86, green: 0.15, blue: 0.47)
        case .graphite: Color(red: 0.35, green: 0.36, blue: 0.40)
        }
    }
}

extension URL {
    /// Favicon via a public service until the engine reports page icons itself.
    var faviconURL: URL? {
        guard let host = host() else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
    }
}
