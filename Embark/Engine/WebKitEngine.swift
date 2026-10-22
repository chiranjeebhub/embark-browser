import WebKit

/// Development engine built on WKWebView. It needs no downloads, so the UI can be built and
/// tried right away while the Chromium engine is brought up. Each profile maps to its own
/// persistent WKWebsiteDataStore, so logins never mix between spaces.
@MainActor
final class WebKitEngine: BrowserEngine {
    private var stores: [Profile.ID: WKWebsiteDataStore] = [:]
    private let processPool = WKProcessPool()

    func makePage(url: URL, profile: Profile) -> BrowserPage {
        let store = stores[profile.id] ?? WKWebsiteDataStore(forIdentifier: profile.id)
        stores[profile.id] = store
        return WebKitPage(url: url, store: store)
    }
}

@MainActor
final class WebKitPage: NSObject, BrowserPage, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    weak var delegate: BrowserPageDelegate?

    init(url: URL, store: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        observations = [
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.report() } },
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.report() } },
        ]
        webView.load(URLRequest(url: url))
    }

    var view: NSView { webView }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func close() {
        observations.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    private func report() {
        delegate?.page(self, didChangeTitle: webView.title, url: webView.url)
    }

    // target=_blank and window.open become new tabs in the current space.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { delegate?.page(self, requestsNewTab: url) }
        return nil
    }
}
