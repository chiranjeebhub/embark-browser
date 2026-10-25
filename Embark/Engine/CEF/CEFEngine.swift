import AppKit

/// Chromium engine via the Chromium Embedded Framework. Built when the ENGINE_CEF flag is set
/// and Vendor/cef is present (see scripts/fetch-cef.sh and docs/ARCHITECTURE.md).
@MainActor
final class CEFEngine: BrowserEngine {
    static let cacheRoot = BrowserStore.supportDirectory.appending(path: "Chromium", directoryHint: .isDirectory)

    func makePage(url: URL, profile: Profile) -> BrowserPage {
        CEFPage(browser: EMBCEFBrowser(url: url, profileDirectory: directory(for: profile)))
    }

    var supportsExtensions: Bool { true }

    func extensions(for profile: Profile) -> [InstalledExtension] {
        ExtensionCatalog.extensions(inProfile: directory(for: profile))
    }

    func removeData(for profile: Profile) {
        try? FileManager.default.removeItem(at: directory(for: profile))
    }

    /// Chromium's profile folder: cookies, logins and extensions, apart from other profiles.
    private func directory(for profile: Profile) -> URL {
        Self.cacheRoot.appending(path: "Profile-\(profile.id.uuidString)", directoryHint: .isDirectory)
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

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, requestsPermissions permissions: [NSNumber], origin: String,
                                requestID: UInt64, respond: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let respond = respond
        MainActor.assumeIsolated {
            let request = PermissionRequest(id: requestID, origin: origin,
                                            permissions: permissions.compactMap { SitePermission(rawValue: $0.intValue) },
                                            respond: { respond($0) })
            delegate?.page(self, requestsPermission: request)
        }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, dismissedPermissionRequest requestID: UInt64) {
        MainActor.assumeIsolated { delegate?.page(self, dismissedPermissionRequest: requestID) }
    }

    // MARK: Page info

    var security: PageSecurity {
        PageSecurity(isSecure: browser.isSecure, hasCertificateError: browser.hasCertificateError,
                     certificate: browser.certificate.map {
                         PageCertificate(subject: $0.subject, issuer: $0.issuer, validFrom: $0.validFrom, validUntil: $0.validUntil)
                     })
    }

    func permission(_ permission: SitePermission) -> PermissionValue {
        PermissionValue(rawValue: browser.permission(EMBSitePermission(rawValue: permission.rawValue)!).rawValue) ?? .default
    }

    func defaultPermission(_ permission: SitePermission) -> PermissionValue {
        PermissionValue(rawValue: browser.defaultPermission(EMBSitePermission(rawValue: permission.rawValue)!).rawValue) ?? .default
    }

    func setPermission(_ permission: SitePermission, to value: PermissionValue) {
        browser.setPermission(EMBSitePermission(rawValue: permission.rawValue)!, value: EMBPermissionValue(rawValue: value.rawValue)!)
    }

    func setAudioMuted(_ muted: Bool) { browser.setAudioMuted(muted) }

    func countCookies(_ completion: @escaping (Int) -> Void) {
        browser.countCookies { completion($0) }
    }

    func clearSiteData(_ completion: @escaping () -> Void) {
        browser.clearSiteData(completion)
    }

    private func report() {
        delegate?.page(self, didChangeTitle: title, url: url)
    }
}
