import Foundation

/// Streaming sites whose video is copy-protected. The Chromium build Embark ships can't play
/// them (no Widevine), so their pages run on macOS's own WebKit engine instead, which has
/// Apple's FairPlay and the H.264 and AAC codecs built in.
enum ProtectedMedia {
    /// Sites, matched with their subdomains (www.netflix.com, open.spotify.com).
    static let hosts: Set<String> = [
        "netflix.com", "primevideo.com", "disneyplus.com", "hotstar.com", "hulu.com",
        "max.com", "hbomax.com", "spotify.com", "tv.apple.com", "music.apple.com",
        "peacocktv.com", "paramountplus.com", "crunchyroll.com", "jiocinema.com",
        "sonyliv.com", "zee5.com", "tidal.com", "deezer.com", "mubi.com", "zee5.in",
    ]

    /// Amazon's video lives under paths of amazon.com and its country sites.
    private static let amazonVideoPaths = ["/gp/video", "/Amazon-Video"]

    static func needsSystemEngine(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased() else { return false }
        if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let labels = host.split(separator: ".")
        if let amazon = labels.firstIndex(of: "amazon"), amazon < labels.count - 1 {
            return amazonVideoPaths.contains { url.path().hasPrefix($0) }
        }
        return false
    }
}
