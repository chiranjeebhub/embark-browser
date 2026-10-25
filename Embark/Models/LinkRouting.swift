import Foundation

extension PreferenceKey {
    /// Links from other apps that no space claims open in a small Little window, as in Arc.
    static let opensLinksInLittleWindow = "opensLinksInLittleWindow"
}

/// Like Arc's Air Traffic Control: a link clicked in another app goes to the space that already
/// has that site as a favorite, or failing that in one of its folders.
enum LinkRouting {
    static func space(for url: URL, in spaces: [Space]) -> Space.ID? {
        guard let host = url.host().map(normalized), !host.isEmpty else { return nil }
        if let space = spaces.first(where: { $0.favorites.contains { matches(host, $0.url) } }) { return space.id }
        return spaces.first { $0.tabs.contains { $0.folderID != nil && matches(host, $0.url) } }?.id
    }

    /// The same site, or a subdomain of it: mail.google.com matches a google.com favorite.
    private static func matches(_ host: String, _ url: URL) -> Bool {
        guard let other = url.host().map(normalized), !other.isEmpty else { return false }
        return host == other || host.hasSuffix("." + other)
    }

    private static func normalized(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}
