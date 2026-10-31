import Foundation
import Testing

/// Which pages run on WebKit for copy-protected video.
struct ProtectedMediaTests {
    private func needs(_ string: String, chosen: Set<String> = []) -> Bool {
        ProtectedMedia.needsSystemEngine(URL(string: string)!, chosen: chosen)
    }

    @Test func streamingSitesAndTheirSubdomains() {
        #expect(needs("https://www.netflix.com/browse"))
        #expect(needs("https://open.spotify.com/track/1"))
        #expect(needs("https://accounts.spotify.com/login"))
        #expect(needs("https://www.hotstar.com/in"))
        #expect(needs("https://tv.apple.com"))
    }

    @Test func amazonOnlyForItsVideoPages() {
        #expect(needs("https://www.amazon.com/gp/video/storefront"))
        #expect(needs("https://www.amazon.in/gp/video/detail/x"))
        #expect(!needs("https://www.amazon.com/dp/B0123"))
    }

    @Test func otherSitesStayOnChromium() {
        #expect(!needs("https://www.youtube.com/watch?v=1"))
        #expect(!needs("https://notnetflix.com"))
        #expect(!needs("https://apple.com"))
        #expect(!needs("about:blank"))
    }

    @Test func h264OnlyVideoSites() {
        #expect(needs("https://x.com/someone/status/1"))
        #expect(needs("https://www.instagram.com/reel/abc"))
        #expect(needs("https://old.reddit.com/r/videos"))
        #expect(needs("https://www.twitch.tv/somechannel"))
        #expect(!needs("https://notx.com"))
    }

    @Test func sitesTheUserMoved() {
        #expect(needs("https://www.bbc.co.uk/news/video", chosen: ["bbc.co.uk"]))
        #expect(!needs("https://www.bbc.co.uk/news/video"))
        #expect(!needs("about:blank", chosen: ["blank"]))
    }

    @Test func siteHostDropsWWW() {
        #expect(ProtectedMedia.siteHost(URL(string: "https://www.bbc.co.uk/news")!) == "bbc.co.uk")
        #expect(ProtectedMedia.siteHost(URL(string: "https://edition.cnn.com")!) == "edition.cnn.com")
        #expect(ProtectedMedia.siteHost(URL(string: "file:///tmp/a.mp4")!) == nil)
    }
}
