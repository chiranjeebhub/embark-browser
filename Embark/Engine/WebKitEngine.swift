import WebKit

/// Development engine built on WKWebView. It needs no downloads, so the UI can be built and
/// tried right away while the Chromium engine is brought up. Each profile maps to its own
/// persistent WKWebsiteDataStore, so logins never mix between spaces.
@MainActor
final class WebKitEngine: BrowserEngine {
    private var stores: [Profile.ID: WKWebsiteDataStore] = [:]

    init() {
        // Settings ▸ Privacy ▸ Start every session signed out.
        if UserDefaults.standard.bool(forKey: PreferenceKey.signsOutAtLaunch) {
            let types = Self.types(for: [.cookies, .storage])
            Task { @MainActor in
                for id in await WKWebsiteDataStore.allDataStoreIdentifiers {
                    await WKWebsiteDataStore(forIdentifier: id).removeData(ofTypes: types, modifiedSince: .distantPast)
                }
            }
        }
    }

    func makePage(url: URL, profile: Profile) -> BrowserPage {
        if profile.isPrivate == true {
            let store = stores[profile.id] ?? .nonPersistent()
            stores[profile.id] = store
            return WebKitPage(url: url, store: store)
        }
        let store = stores[profile.id] ?? WKWebsiteDataStore(forIdentifier: profile.id)
        stores[profile.id] = store
        return WebKitPage(url: url, store: store)
    }

    func removeData(for profile: Profile) {
        stores[profile.id] = nil
        guard profile.isPrivate != true else { return }
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: profile.id) }
    }

    func clearBrowsingData(_ data: BrowsingData, for profile: Profile, completion: @escaping @MainActor () -> Void) {
        let store = stores[profile.id] ?? WKWebsiteDataStore(forIdentifier: profile.id)
        store.removeData(ofTypes: Self.types(for: data), modifiedSince: .distantPast) { completion() }
    }

    private static func types(for data: BrowsingData) -> Set<String> {
        let cookies: Set = [WKWebsiteDataTypeCookies]
        let cache: Set = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
        var types: Set<String> = []
        if data.contains(.cookies) { types.formUnion(cookies) }
        if data.contains(.cache) { types.formUnion(cache) }
        if data.contains(.storage) { types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cookies).subtracting(cache)) }
        return types
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
            webView.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.reportLoading() } },
            webView.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.reportLoading() } },
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
    func stopLoading() { webView.stopLoading() }
    var zoomFactor: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }
    func print() { webView.printOperation(with: .shared).runModal(for: webView.window ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil) }

    func close() {
        observations.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    private func reportLoading() {
        delegate?.page(self, didChangeLoading: webView.isLoading, progress: webView.estimatedProgress)
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
