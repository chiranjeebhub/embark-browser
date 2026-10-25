import Foundation

/// Things the ⌘T bar can do besides opening pages, found by typing part of their name.
enum BrowserAction: String, CaseIterable, Identifiable {
    case newWindow, newPrivateWindow, newSpace, newFolder, newSplit
    case addToFavorites, copyURL, reload, closeTab, reopenClosedTab
    case findOnPage, zoomIn, zoomOut, actualSize, print, developerTools
    case showHistory, clearHistory, toggleSidebar, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newWindow: "New Window"
        case .newPrivateWindow: "New Private Window"
        case .newSpace: "New Space"
        case .newFolder: "New Folder"
        case .newSplit: "New Split View"
        case .addToFavorites: "Add to Favorites"
        case .copyURL: "Copy URL"
        case .reload: "Reload Page"
        case .closeTab: "Close Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .findOnPage: "Find on Page"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .print: "Print"
        case .developerTools: "Developer Tools"
        case .showHistory: "Show History"
        case .clearHistory: "Clear History"
        case .toggleSidebar: "Toggle Sidebar"
        case .settings: "Settings"
        }
    }

    /// Other words people type for it.
    private var keywords: [String] {
        switch self {
        case .newPrivateWindow: ["incognito"]
        case .newSplit: ["side by side"]
        case .addToFavorites: ["pin", "bookmark"]
        case .copyURL: ["link", "address"]
        case .reload: ["refresh"]
        case .developerTools: ["inspect", "console", "devtools"]
        case .clearHistory: ["delete", "browsing data"]
        case .toggleSidebar: ["hide", "show"]
        case .settings: ["preferences"]
        default: []
        }
    }

    var symbol: String {
        switch self {
        case .newWindow: "macwindow.badge.plus"
        case .newPrivateWindow: "eyeglasses"
        case .newSpace: "plus.square.on.square"
        case .newFolder: "folder.badge.plus"
        case .newSplit: "rectangle.split.2x1"
        case .addToFavorites: "star"
        case .copyURL: "link"
        case .reload: "arrow.clockwise"
        case .closeTab: "xmark"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .findOnPage: "text.magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .actualSize: "1.magnifyingglass"
        case .print: "printer"
        case .developerTools: "hammer"
        case .showHistory: "clock"
        case .clearHistory: "clock.badge.xmark"
        case .toggleSidebar: "sidebar.left"
        case .settings: "gearshape"
        }
    }

    /// Actions whose name or keywords start with each typed word, best first. Needs at least
    /// two letters so typing a site name doesn't fill the list with actions.
    static func matching(_ query: String) -> [BrowserAction] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard query.trimmingCharacters(in: .whitespaces).count >= 2, !words.isEmpty else { return [] }
        func score(_ action: BrowserAction) -> Int? {
            let titleWords = action.title.lowercased().split(separator: " ").map(String.init)
            let keywordWords = action.keywords.flatMap { $0.split(separator: " ").map(String.init) }
            var total = 0
            for word in words {
                if titleWords.contains(where: { $0.hasPrefix(word) }) { total += 2 }
                else if keywordWords.contains(where: { $0.hasPrefix(word) }) { total += 1 }
                else { return nil }
            }
            if action.title.lowercased().hasPrefix(query.lowercased()) { total += 3 }
            return total
        }
        return allCases.compactMap { action in score(action).map { (action, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
