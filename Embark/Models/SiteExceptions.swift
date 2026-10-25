import Foundation

/// A site's saved permission in a Chromium profile, such as camera allowed for meet.google.com.
struct SiteException: Identifiable, Hashable {
    /// "https://meet.google.com", or a pattern like "[*.]example.com".
    var origin: String
    /// Chromium's content setting name, such as "media_stream_camera".
    var contentType: String
    var isAllowed: Bool

    var id: String { "\(contentType) \(origin)" }

    /// The origin without its scheme and default port, for display.
    var host: String {
        var text = origin
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        for port in [":443", ":80"] where text.hasSuffix(port) { text.removeLast(port.count) }
        return text
    }
}

enum ChromiumPreferences {
    /// The exceptions a profile saved for `contentTypes`, from its `Preferences` file. CEF has
    /// no API that lists them. Chromium writes the file a few seconds after a change.
    static func siteExceptions(_ data: Data, contentTypes: [String]) -> [SiteException] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exceptions = ((root["profile"] as? [String: Any])?["content_settings"] as? [String: Any])?["exceptions"]
                as? [String: Any] else { return [] }
        var result: [SiteException] = []
        for type in contentTypes {
            for (pattern, value) in exceptions[type] as? [String: Any] ?? [:] {
                // 1 allows, 2 blocks; anything else (ask, or no setting) isn't an exception.
                guard let setting = (value as? [String: Any])?["setting"] as? Int, setting == 1 || setting == 2 else { continue }
                // Keys are "primary,secondary"; the secondary is "*" for these settings.
                let primary = String(pattern.split(separator: ",", maxSplits: 1).first ?? "")
                guard !primary.isEmpty, primary != "*" else { continue }
                result.append(SiteException(origin: primary, contentType: type, isAllowed: setting == 1))
            }
        }
        return result.sorted { ($0.host, $0.contentType) < ($1.host, $1.contentType) }
    }
}
