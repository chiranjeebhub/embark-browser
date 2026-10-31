import Foundation

/// Sites whose video the Chromium build Embark ships can't play, so their pages run on macOS's
/// own WebKit engine instead, which has Apple's FairPlay and the H.264 and AAC codecs built in.
/// Streaming sites are copy-protected (no Widevine); video sites serve only H.264, which
/// prebuilt CEF leaves out (see docs/CODECS.md).
enum ProtectedMedia {
    /// Sites, matched with their subdomains (www.netflix.com, open.spotify.com).
    static let hosts: Set<String> = [
        "netflix.com", "primevideo.com", "disneyplus.com", "hotstar.com", "hulu.com",
        "max.com", "hbomax.com", "spotify.com", "tv.apple.com", "music.apple.com",
        "peacocktv.com", "paramountplus.com", "crunchyroll.com", "jiocinema.com",
        "sonyliv.com", "zee5.com", "tidal.com", "deezer.com", "mubi.com", "zee5.in",
    ]

    /// Sites whose own video is H.264 only, with no VP9 or AV1 to fall back on.
    static let h264Hosts: Set<String> = [
        "x.com", "twitter.com", "instagram.com", "reddit.com", "twitch.tv", "vimeo.com", "tiktok.com",
    ]

    /// Amazon's video lives under paths of amazon.com and its country sites.
    private static let amazonVideoPaths = ["/gp/video", "/Amazon-Video"]

    /// `chosen` are sites the user moved to WebKit themselves ("Play in Safari Engine").
    static func needsSystemEngine(_ url: URL, chosen: Set<String> = []) -> Bool {
        guard let host = webHost(url) else { return false }
        if [hosts, h264Hosts, chosen].contains(where: { matches(host, $0) }) { return true }
        let labels = host.split(separator: ".")
        if let amazon = labels.firstIndex(of: "amazon"), amazon < labels.count - 1 {
            return amazonVideoPaths.contains { url.path().hasPrefix($0) }
        }
        return false
    }

    /// The host to remember when the user moves a site to WebKit: www. is dropped so the
    /// choice covers the whole site.
    static func siteHost(_ url: URL) -> String? {
        guard let host = webHost(url) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func webHost(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url.host()?.lowercased()
    }

    private static func matches(_ host: String, _ set: Set<String>) -> Bool {
        set.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
