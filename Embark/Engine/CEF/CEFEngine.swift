import AppKit

/// Chromium engine via the Chromium Embedded Framework. Built when the ENGINE_CEF flag is set
/// and Vendor/cef is present (see scripts/fetch-cef.sh and docs/ARCHITECTURE.md).
@MainActor
final class CEFEngine: BrowserEngine {
    static let cacheRoot = BrowserStore.supportDirectory.appending(path: "Chromium", directoryHint: .isDirectory)

    func makePage(url: URL, profile: Profile) -> BrowserPage {
        if profile.isPrivate == true {
            return CEFPage(browser: EMBCEFBrowser(url: url, privateSessionID: profile.id.uuidString))
        }
        let browser = EMBCEFBrowser(url: url, profileDirectory: directory(for: profile))
        // Notices sign-ins, for saved passwords. Private windows save none.
        browser.documentScript = Self.loginScript
        browser.loginMessagePrefix = LoginScript.consolePrefix
        return CEFPage(browser: browser)
    }

    private static let loginScript = LoginScript.source(for: .console)

    var supportsExtensions: Bool { true }

    func extensions(for profile: Profile) -> [InstalledExtension] {
        ExtensionCatalog.extensions(inProfile: directory(for: profile))
    }

    func removeData(for profile: Profile) {
        if profile.isPrivate == true {
            EMBCEFBrowser.endPrivateSession(profile.id.uuidString)
            return
        }
        try? FileManager.default.removeItem(at: directory(for: profile))
    }

    private var downloadObserver: DownloadObserver?

    func observeDownloads(destination: @escaping (String) -> URL?, update: @escaping (Download) -> Void) {
        let observer = DownloadObserver(destination: destination, update: update)
        downloadObserver = observer
        EMBCEFDownloads.observer = observer
    }

    func cancelDownload(_ id: Download.ID) { EMBCEFDownloads.cancel(id) }

    // MARK: Site settings and browsing data

    var supportsSiteSettings: Bool { true }

    func setBlocksThirdPartyCookies(_ block: Bool) { EMBCEFRuntime.setBlocksThirdPartyCookies(block) }

    func siteExceptions(for profile: Profile) -> [SiteException] {
        guard let data = try? Data(contentsOf: directory(for: profile).appending(path: "Preferences")) else { return [] }
        return ChromiumPreferences.siteExceptions(data, contentTypes: SitePermission.allCases.map(\.chromiumName))
    }

    func resetSiteException(_ exception: SiteException, for profile: Profile) {
        guard let permission = SitePermission(chromiumName: exception.contentType),
              let kind = EMBSitePermission(rawValue: permission.rawValue) else { return }
        EMBCEFRuntime.resetPermission(kind, origin: exception.origin, profileDirectory: directory(for: profile))
    }

    /// Chromium keeps its cache and site storage open while it runs.
    var browsingDataClearedAtLaunch: BrowsingData { [.cache, .storage] }

    func clearBrowsingData(_ data: BrowsingData, for profile: Profile, completion: @escaping @MainActor () -> Void) {
        let later = data.intersection(browsingDataClearedAtLaunch)
        if !later.isEmpty {
            var pending = Self.pendingClears
            pending[profile.id.uuidString] = (pending[profile.id.uuidString] ?? 0) | later.rawValue
            Self.pendingClears = pending
        }
        guard data.contains(.cookies) else { completion(); return }
        EMBCEFRuntime.deleteCookies(inProfileDirectory: directory(for: profile)) {
            MainActor.assumeIsolated { completion() }
        }
    }

    /// Profile id to the `BrowsingData` queued for the next launch.
    private static var pendingClears: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "pendingBrowsingDataClears") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "pendingBrowsingDataClears") }
    }

    /// Before Chromium starts: removes data queued by Clear Browsing Data, and with "Start
    /// every session signed out" every profile's cookies and site storage.
    static func clearDataBeforeLaunch() {
        let files = FileManager.default
        let signsOut = UserDefaults.standard.bool(forKey: PreferenceKey.signsOutAtLaunch)
        let pending = pendingClears
        let profiles = (try? files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)) ?? []
        for directory in profiles where directory.lastPathComponent.hasPrefix("Profile-") {
            let id = String(directory.lastPathComponent.dropFirst("Profile-".count))
            var data = BrowsingData(rawValue: pending[id] ?? 0)
            if signsOut { data.formUnion([.cookies, .storage]) }
            for path in paths(for: data) { try? files.removeItem(at: directory.appending(path: path)) }
        }
        UserDefaults.standard.removeObject(forKey: "pendingBrowsingDataClears")
    }

    /// Where Chromium keeps each kind of data inside a profile folder.
    private static func paths(for data: BrowsingData) -> [String] {
        var paths: [String] = []
        if data.contains(.cookies) {
            paths += ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"]
        }
        if data.contains(.cache) {
            paths += ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
                      "Service Worker/CacheStorage", "Service Worker/ScriptCache"]
        }
        if data.contains(.storage) {
            paths += ["Local Storage", "Session Storage", "IndexedDB", "databases", "File System", "Service Worker",
                      "WebStorage", "Shared Dictionary", "shared_proto_db", "blob_storage"]
        }
        return paths
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
    func find(_ text: String, forward: Bool, findNext: Bool) { browser.find(text, forward: forward, findNext: findNext) }
    func stopFinding() { browser.stopFinding() }
    func exitFullscreen() { browser.exitFullscreen() }
    func stopLoading() { browser.stopLoading() }
    var zoomFactor: Double {
        get { browser.zoomFactor }
        set { browser.zoomFactor = newValue }
    }
    func print() { browser.print() }
    func showDevTools() { browser.showDevTools() }

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

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didFindMatches count: Int, active: Int) {
        MainActor.assumeIsolated { delegate?.page(self, didFindMatches: count, active: active) }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didChangeFullscreen fullscreen: Bool) {
        MainActor.assumeIsolated { delegate?.page(self, didChangeFullscreen: fullscreen) }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didChangeLoading isLoading: Bool, progress: Double) {
        MainActor.assumeIsolated { delegate?.page(self, didChangeLoading: isLoading, progress: progress) }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didChangeFavicon png: Data?) {
        MainActor.assumeIsolated { delegate?.page(self, didChangeFavicon: png) }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, requestsCredentialsFor host: String, realm: String?, isProxy: Bool,
                                respond: @escaping (String?, String?) -> Void) {
        nonisolated(unsafe) let respond = respond
        MainActor.assumeIsolated {
            delegate?.page(self, requestsCredentials: CredentialRequest(host: host, realm: realm, isProxy: isProxy) { respond($0, $1) })
        }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, certificateErrorFor url: URL, description: String,
                                respond: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let respond = respond
        MainActor.assumeIsolated {
            delegate?.page(self, hitCertificateError: CertificateWarning(url: url, description: description) { respond($0) })
        }
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, didPostLoginMessage message: String) {
        MainActor.assumeIsolated { delegate?.page(self, didPostLoginMessage: message) }
    }

    func fillLogin(username: String, password: String) {
        browser.runScript(LoginScript.fillCall(username: username, password: password))
    }

    nonisolated func cefBrowser(_ browser: EMBCEFBrowser, renderProcessTerminatedOutOfMemory outOfMemory: Bool) {
        MainActor.assumeIsolated { delegate?.page(self, didCrashOutOfMemory: outOfMemory) }
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

/// Turns the bridge's download snapshots into `Download` values.
private final class DownloadObserver: NSObject, EMBCEFDownloadObserver {
    let destination: (String) -> URL?
    let update: (Download) -> Void

    init(destination: @escaping (String) -> URL?, update: @escaping (Download) -> Void) {
        self.destination = destination
        self.update = update
    }

    func cefDownloadDestination(suggestedName name: String) -> URL? { destination(name) }

    func cefDownloadDidUpdate(_ download: EMBCEFDownload) {
        let state: Download.State = switch download.state {
        case .complete: .complete
        case .canceled: .canceled
        case .failed: .failed
        default: .inProgress
        }
        update(Download(id: download.identifier, url: download.url, fileName: download.fileName, fileURL: download.fileURL,
                        receivedBytes: download.receivedBytes,
                        totalBytes: download.totalBytes >= 0 ? download.totalBytes : nil,
                        bytesPerSecond: download.bytesPerSecond, state: state))
    }
}
