import Foundation
import Testing

/// Which pages run on WebKit for copy-protected video.
struct ProtectedMediaTests {
    private func needs(_ string: String) -> Bool { ProtectedMedia.needsSystemEngine(URL(string: string)!) }

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
}
