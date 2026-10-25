import SwiftUI

/// A browsing profile: its own cookies, logins, cache and history on disk.
struct Profile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Extensions shown as tiles at the top of the extensions popover, in order. Optional so
    /// older saved state loads.
    var pinnedExtensionIDs: [String]?
    /// The color of the profile's badge. Optional so older saved state loads.
    var tint: SpaceTint?
    /// A private window's profile: nothing it does is kept after the window closes.
    var isPrivate: Bool?
}

/// A site pinned to a space's favorites grid. Like Arc, a favorite is its own tab: it has its
/// own page, separate from the tab list.
struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// Where the favorite starts. Its page may have navigated elsewhere since.
    var url: URL
    /// The favorite's page, made the first time it's opened (or brought along when a tab is
    /// pinned). Optional so older saved state loads.
    var tab: BrowserTab?
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

/// A space groups favorites and tabs under one profile and one theme.
struct Space: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// The color saved before themes; `theme` replaces it (see `resolvedTheme`).
    var tint: SpaceTint?
    /// Colors, grain and appearance. nil for state saved before themes.
    var theme: SpaceTheme?
    /// Shown in the space switcher: an SF Symbol, or text (see `SpaceIcon.Kind`). nil shows the
    /// name's first letter.
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
        "books.vertical.fill", "newspaper.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "paintbrush.fill", "paintpalette.fill",
        "pencil.and.scribble", "camera.fill", "photo.fill", "film.fill", "music.note", "headphones",
        "gamecontroller.fill", "tv.fill", "cart.fill", "bag.fill", "creditcard.fill", "banknote.fill",
        "chart.line.uptrend.xyaxis", "chart.pie.fill", "building.2.fill", "storefront.fill", "airplane",
        "car.fill", "map.fill", "globe.americas.fill", "heart.fill", "star.fill", "flag.fill", "bookmark.fill",
        "leaf.fill", "tree.fill", "flame.fill", "bolt.fill", "drop.fill", "sun.max.fill", "moon.fill",
        "cloud.fill", "sparkles", "wand.and.stars", "lightbulb.fill", "brain.head.profile", "atom", "flask.fill",
        "stethoscope", "figure.run", "dumbbell.fill", "fork.knife", "cup.and.saucer.fill", "pawprint.fill",
        "gift.fill", "calendar", "envelope.fill", "bubble.left.and.bubble.right.fill", "lock.fill", "shield.fill",
    ]

    /// Emoji offered in the icon picker; any other can be typed.
    static let emoji = [
        "💼", "🏠", "🎓", "🧪", "🎨", "🎧", "🛒", "✈️", "📚", "💡", "🚀", "🌱",
        "🔥", "⭐️", "❤️", "🎮", "📈", "🧘", "☕️", "🌙", "🐶", "⚽️", "🍳", "🏝️",
        "💻", "📷", "🎬", "🎵", "🧠", "💰", "🏋️", "🌍", "🌸", "🍀", "⚡️", "🦄",
    ]

    /// What a space's `icon` holds.
    enum Kind: Equatable {
        /// An SF Symbol name.
        case symbol(String)
        /// An emoji or up to two letters, saved as "text:" and the text.
        case text(String)
        /// None: the space's first letter.
        case initial
    }

    private static let textPrefix = "text:"

    static func kind(of icon: String?) -> Kind {
        guard let icon, !icon.isEmpty else { return .initial }
        if icon.hasPrefix(textPrefix) {
            let text = String(icon.dropFirst(textPrefix.count))
            return text.isEmpty ? .initial : .text(text)
        }
        return .symbol(icon)
    }

    /// The `icon` value for text: an emoji, or one or two letters. Empty text means none.
    static func text(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : textPrefix + String(trimmed.prefix(2))
    }

    /// Symbols that fit a space's name, best first: "Work" suggests a briefcase.
    static func suggestions(for name: String) -> [String] {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        var result: [String] = []
        for word in words {
            // Short keywords must match a whole word, so "me" doesn't match "meeting".
            for (keywords, symbols) in keywordSymbols
            where keywords.contains(where: { word == $0 || ($0.count >= 3 && word.hasPrefix($0)) }) {
                for symbol in symbols where !result.contains(symbol) { result.append(symbol) }
            }
        }
        return result
    }

    private static let keywordSymbols: [([String], [String])] = [
        (["work", "job", "office", "business", "client"], ["briefcase.fill", "building.2.fill", "chart.line.uptrend.xyaxis"]),
        (["home", "personal", "family", "life", "me"], ["house.fill", "person.fill", "heart.fill"]),
        (["study", "school", "class", "uni", "college", "learn", "course"], ["graduationcap.fill", "book.fill", "brain.head.profile"]),
        (["read", "book", "news"], ["book.fill", "books.vertical.fill", "newspaper.fill"]),
        (["code", "dev", "program", "engineer", "project", "side", "build"], ["chevron.left.forwardslash.chevron.right", "terminal.fill", "hammer.fill"]),
        (["design", "art", "draw", "paint", "creative"], ["paintbrush.fill", "paintpalette.fill", "pencil.and.scribble"]),
        (["shop", "buy", "store"], ["cart.fill", "bag.fill", "creditcard.fill"]),
        (["money", "finance", "bank", "invest", "budget", "tax"], ["banknote.fill", "creditcard.fill", "chart.pie.fill"]),
        (["travel", "trip", "vacation", "holiday", "flight"], ["airplane", "map.fill", "globe.americas.fill"]),
        (["music", "song", "audio", "podcast"], ["music.note", "headphones"]),
        (["game", "gaming", "play"], ["gamecontroller.fill"]),
        (["photo", "camera", "picture"], ["camera.fill", "photo.fill"]),
        (["video", "movie", "film", "watch", "stream"], ["film.fill", "tv.fill"]),
        (["health", "fitness", "gym", "sport", "run", "workout"], ["figure.run", "dumbbell.fill", "heart.fill"]),
        (["food", "cook", "recipe", "kitchen"], ["fork.knife", "cup.and.saucer.fill"]),
        (["research", "science", "lab"], ["flask.fill", "atom", "lightbulb.fill"]),
        (["idea", "think", "note"], ["lightbulb.fill", "sparkles"]),
        (["mail", "email", "chat", "social"], ["envelope.fill", "bubble.left.and.bubble.right.fill"]),
        (["pet", "dog", "cat"], ["pawprint.fill"]),
    ]
}

enum SpaceTint: String, Codable, CaseIterable {
    case purple, indigo, blue, teal, green, yellow, orange, red, pink, graphite

    var color: Color {
        switch self {
        case .purple: Color(red: 0.54, green: 0.31, blue: 0.85)
        case .indigo: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .blue: Color(red: 0.04, green: 0.39, blue: 0.85)
        case .teal: Color(red: 0.06, green: 0.58, blue: 0.53)
        case .green: Color(red: 0.2, green: 0.63, blue: 0.32)
        case .yellow: Color(red: 0.84, green: 0.63, blue: 0.08)
        case .orange: Color(red: 0.91, green: 0.35, blue: 0.05)
        case .red: Color(red: 0.84, green: 0.2, blue: 0.23)
        case .pink: Color(red: 0.86, green: 0.15, blue: 0.47)
        case .graphite: Color(red: 0.35, green: 0.36, blue: 0.40)
        }
    }
}
