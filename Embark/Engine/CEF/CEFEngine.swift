import AppKit

/// Chromium engine via the Chromium Embedded Framework. Built when the ENGINE_CEF flag is set
/// and Vendor/cef is present (see scripts/fetch-cef.sh and docs/ARCHITECTURE.md).
@MainActor
final class CEFEngine: BrowserEngine {
    static let cacheRoot = BrowserStore.supportDirectory.appending(path: "Chromium", directoryHint: .isDirectory)

    func makePage(url: URL, profile: Profile) -> BrowserPage {
        let directory = Self.cacheRoot.appending(path: "Profile-\(profile.id.uuidString)", directoryHint: .isDirectory)
        return CEFPage(browser: EMBCEFBrowser(url: url, profileDirectory: directory))
    }
}

@MainActor
final class CEFPage: NSObject, BrowserPage, EMBCEFBrowserDelegate {
    private let browser: EMBCEFBrowser
    private var title: String?
    private var url: URL?
    weak var delegate: BrowserPageDelegate?

    init(browser: EMBCEFBrowser) {
        self.browser = browser
        super.init()
        browser.delegate = self
    }

    var view: NSView { browser.view }
    var canGoBack: Bool { browser.canGoBack }
    var canGoForward: Bool { browser.canGoForward }
    func load(_ url: URL) { browser.load(url) }
    func goBack() { browser.goBack() }
    func goForward() { browser.goForward() }
    func reload() { browser.reload() }
    func close() { browser.close() }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didChangeTitle title: String?) {
        MainActor.assumeIsolated { self.title = title; report() }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didChangeURL url: URL?) {
        MainActor.assumeIsolated { self.url = url; report() }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, requestsNewTab url: URL) {
        MainActor.assumeIsolated { delegate?.page(self, requestsNewTab: url) }
    }

    nonisolated func cefBrowserDidChangeNavigationState(_ browser: EMBCEFBrowser) {
        MainActor.assumeIsolated { report() }
    }

    private func report() {
        delegate?.page(self, didChangeTitle: title, url: url)
    }
}
