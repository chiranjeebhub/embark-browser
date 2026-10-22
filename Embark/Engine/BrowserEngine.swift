import AppKit

/// The rendering engine behind every tab. Embark's UI only talks to these protocols, so the
/// Chromium (CEF) engine and the WebKit development engine are interchangeable.
@MainActor
protocol BrowserEngine: AnyObject {
    func makePage(url: URL, profile: Profile) -> BrowserPage
}

@MainActor
protocol BrowserPage: AnyObject {
    var view: NSView { get }
    var delegate: BrowserPageDelegate? { get set }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    /// Releases the renderer. The page is discarded afterwards.
    func close()
}

@MainActor
protocol BrowserPageDelegate: AnyObject {
    func page(_ page: BrowserPage, didChangeTitle title: String?, url: URL?)
    func page(_ page: BrowserPage, requestsNewTab url: URL)
}

enum Engines {
    @MainActor static func make() -> BrowserEngine {
        #if ENGINE_CEF
        return CEFEngine()
        #else
        return WebKitEngine()
        #endif
    }
}
