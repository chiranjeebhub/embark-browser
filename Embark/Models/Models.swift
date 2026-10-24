import SwiftUI

/// A browsing profile: its own cookies, logins, cache and history on disk.
struct Profile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Extensions shown as tiles at the top of the extensions popover, in order. Optional so
    /// older saved state loads.
    var pinnedExtensionIDs: [String]?
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
    /// The folder the tab is in; nil for the space's loose tabs.
    var folderID: Folder.ID?
    /// A folder's tab whose page was closed: it stays in the folder, dimmed, until reopened.
    /// Optional so older saved state loads.
    var isUnloaded: Bool?
}

/// A space groups favorites and tabs under one profile and one tint.
struct Space: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var tint: SpaceTint
    /// SF Symbol shown in the space switcher. nil shows the name's first letter.
    var icon: String?
    var profileID: Profile.ID
    var favorites: [Favorite] = []
    var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID?
    /// Recently closed tabs, newest last, for the Library. Optional so older saved state loads.
    var recentlyClosed: [BrowserTab]?
    /// Tabs shown side by side. Optional so older saved state loads.
    var splits: [Split]?
    /// Folders in the tab list, siblings in this order. Optional so older saved state loads.
    var folders: [Folder]?
}

/// Two to four tabs of a space shown side by side (or stacked) as one item in the tab list.
/// The panes stay ordinary tabs; the space's selected tab is the active pane.
struct Split: Identifiable, Codable, Hashable {
    var id = UUID()
    var tabIDs: [BrowserTab.ID]
    var isVertical = false
    /// Each pane's share of the space, summing to 1.
    var fractions: [Double]

    static let maxPanes = 4

    init(tabIDs: [BrowserTab.ID], isVertical: Bool = false) {
        self.tabIDs = tabIDs
        self.isVertical = isVertical
        fractions = Array(repeating: 1 / Double(tabIDs.count), count: tabIDs.count)
    }

    mutating func evenOut() {
        fractions = Array(repeating: 1 / Double(tabIDs.count), count: tabIDs.count)
    }
}

enum SpaceIcon {
    /// Symbols offered when creating or editing a space.
    static let choices = [
        "house.fill", "briefcase.fill", "person.fill", "person.2.fill", "graduationcap.fill", "book.fill",
        "hammer.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.fill", "camera.fill", "music.note", "gamecontroller.fill",
        "cart.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "airplane", "heart.fill", "star.fill",
        "leaf.fill", "flame.fill", "bolt.fill", "globe.americas.fill", "sparkles", "moon.fill",
    ]
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
