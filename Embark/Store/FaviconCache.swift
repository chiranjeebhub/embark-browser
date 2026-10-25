import AppKit
import Observation

/// Site icons as pages report them, kept on disk by host so favorites and tabs show them
/// before their pages load. Sites never visited show a letter instead: asking a web service
/// for icons would tell it every site in the sidebar.
@MainActor
@Observable
final class FaviconCache {
    static let shared = FaviconCache()

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var missing: Set<String> = []
    @ObservationIgnored private let folder = BrowserStore.supportDirectory.appending(path: "Favicons", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> NSImage? {
        guard let host = Self.key(for: url) else { return nil }
        if let image = images[host] { return image }
        guard !missing.contains(host) else { return nil }
        if let image = NSImage(contentsOf: file(for: host)) {
            images[host] = image
            return image
        }
        missing.insert(host)
        return nil
    }

    /// Saves a page's icon for its site. Private windows don't call this.
    func store(_ png: Data, for url: URL) {
        guard let host = Self.key(for: url), let image = NSImage(data: png) else { return }
        missing.remove(host)
        images[host] = image
        try? png.write(to: file(for: host), options: .atomic)
    }

    private func file(for host: String) -> URL { folder.appending(path: "\(host).png") }

    /// "www.github.com" and "github.com" share an icon.
    private static func key(for url: URL) -> String? {
        guard var host = url.host()?.lowercased(), !host.isEmpty, !host.contains("/") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
