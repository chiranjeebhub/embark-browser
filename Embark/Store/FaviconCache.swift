import AppKit
import Observation

/// Site icons as pages report them, kept on disk by host so favorites and tabs show them
/// before their pages load. Sites never visited show a letter instead: asking a web service
/// for icons would tell it every site in the sidebar.
///
/// Each site's icon is observed on its own, so an icon arriving redraws only the rows showing
/// that site. Icons are written off the main thread.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    @MainActor
    @Observable
    final class Icon {
        private(set) var image: NSImage?
        /// The PNG on disk, to skip writing the same icon again on every visit.
        @ObservationIgnored var png: Data?
        @ObservationIgnored var isRead = false

        func setImage(_ image: NSImage) { self.image = image }

        /// For the first read, made while a view is reading `image`: changing an observed
        /// value during a view update would redraw it again for nothing.
        func setImageWithoutNotifying(_ image: NSImage) { _image = image }
    }

    private var icons: [String: Icon] = [:]
    private let folder = BrowserStore.supportDirectory.appending(path: "Favicons", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> NSImage? {
        guard let host = Self.key(for: url) else { return nil }
        let icon = icon(for: host)
        if !icon.isRead {
            // Read once per site, while the row first draws, so it never flashes its letter.
            // The files are a few KB. Nothing observed changes here, so no other row redraws.
            icon.isRead = true
            if let png = try? Data(contentsOf: file(for: host)), let image = NSImage(data: png) {
                icon.png = png
                icon.setImageWithoutNotifying(image)
            }
        }
        return icon.image
    }

    /// Saves a page's icon for its site. Private windows don't call this.
    func store(_ png: Data, for url: URL) {
        guard let host = Self.key(for: url) else { return }
        let icon = icon(for: host)
        icon.isRead = true
        guard icon.png != png, let image = NSImage(data: png) else { return }
        icon.png = png
        icon.setImage(image)
        let file = file(for: host)
        Task.detached(priority: .utility) { try? png.write(to: file, options: .atomic) }
    }

    private func icon(for host: String) -> Icon {
        if let icon = icons[host] { return icon }
        let icon = Icon()
        icons[host] = icon
        return icon
    }

    private func file(for host: String) -> URL { folder.appending(path: "\(host).png") }

    /// "www.github.com" and "github.com" share an icon.
    private static func key(for url: URL) -> String? {
        guard var host = url.host()?.lowercased(), !host.isEmpty, !host.contains("/") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
