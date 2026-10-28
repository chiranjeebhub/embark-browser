import AppKit
import Observation

/// Keeps one live page per open tab so switching is instant, and puts tabs nobody has
/// looked at for a while to sleep to keep memory low. A sleeping tab reloads when shown.
@MainActor
@Observable
final class PagePool: BrowserPageDelegate {
    @ObservationIgnored private let engine: BrowserEngine
    /// macOS's WebKit, for streaming sites the main engine can't play (see ProtectedMedia).
    /// nil when the main engine is WebKit already.
    @ObservationIgnored private let mediaEngine: BrowserEngine?
    /// Tabs whose page runs on `mediaEngine`.
    @ObservationIgnored private var mediaPages: Set<BrowserTab.ID> = []
    /// Bumped when a tab's page moves to the other engine, so its host shows the new page.
    private(set) var engineSwitches = 0
    /// Tabs whose page crashed, and whether it ran out of memory, until they're reloaded.
    private(set) var crashedTabs: [BrowserTab.ID: Bool] = [:]
    @ObservationIgnored private var pages: [BrowserTab.ID: BrowserPage] = [:]
    @ObservationIgnored private var tabIDs: [ObjectIdentifier: BrowserTab.ID] = [:]
    /// The window in front. New tabs from pages open there.
    @ObservationIgnored private(set) weak var store: BrowserStore?
    /// Changes when another window comes to the front, so pages move to it (a page can only
    /// be in one window).
    private(set) var activeStoreID: ObjectIdentifier?
    /// Pages visited, per profile.
    let history = HistoryStore()
    /// Each open page's profile and the address last recorded for it.
    @ObservationIgnored private var pageProfiles: [BrowserTab.ID: Profile.ID] = [:]
    @ObservationIgnored private var profilesByTab: [BrowserTab.ID: Profile] = [:]
    @ObservationIgnored private var recordedURLs: [BrowserTab.ID: URL] = [:]
    @ObservationIgnored private var liveTitles: [BrowserTab.ID: String] = [:]
    @ObservationIgnored private var liveURLs: [BrowserTab.ID: URL] = [:]
    /// Pages of private windows, which keep no history or icons.
    @ObservationIgnored private var privatePages: Set<BrowserTab.ID> = []
    /// Sign-in prompts and certificate warnings waiting on each tab.
    private(set) var credentialRequests: [BrowserTab.ID: CredentialRequest] = [:]
    private(set) var certificateWarnings: [BrowserTab.ID: CertificateWarning] = [:]
    @ObservationIgnored private var suspendedDropTypes: [(NSView, [NSPasteboard.PasteboardType])] = []
    /// Bumped when navigation state changes so toolbar buttons refresh.
    private(set) var revision = 0
    /// Permission prompts waiting for an answer, oldest first.
    private(set) var permissionRequests: [TabPermissionRequest] = []
    /// Permissions each site asked for this session, so page info can list them.
    private(set) var usedPermissions: [String: Set<SitePermission>] = [:]

    /// The tab whose find bar is open.
    private(set) var findTabID: BrowserTab.ID?
    /// Matches for the open find bar; nil until the page answers.
    private(set) var findResult: (count: Int, active: Int)?
    /// The last text searched for, offered again when the find bar reopens.
    @ObservationIgnored var lastFindText = ""
    /// Bumped by ⌘F while the bar is already open, to focus its field again.
    private(set) var findFocusRequest = 0
    /// Load progress, 0 to 1, of the tabs that are loading.
    private(set) var loadingProgress: [BrowserTab.ID: Double] = [:]
    /// Zoom picked for each site, kept across launches.
    @ObservationIgnored private var siteZoom: [String: Double] =
        UserDefaults.standard.dictionary(forKey: "SiteZoom") as? [String: Double] ?? [:]
    @ObservationIgnored private var zoomedHosts: [BrowserTab.ID: String] = [:]
    /// Shown briefly over the page after the zoom changes.
    private(set) var zoomNotice: (tabID: BrowserTab.ID, factor: Double, count: Int)?
    /// The tab showing a video (or other element) full screen.
    private(set) var fullscreenTabID: BrowserTab.ID?

    /// Downloads this session, newest first.
    private(set) var downloads: [Download] = []
    /// Bumped when a download starts, so the sidebar can show the list.
    private(set) var downloadStartCount = 0

    init(engine: BrowserEngine = Engines.make(), mediaEngine: BrowserEngine? = Engines.makeMediaEngine()) {
        self.engine = engine
        self.mediaEngine = mediaEngine
        engine.observeDownloads { name in
            Download.destination(for: name, in: Self.downloadsFolder)
        } update: { [weak self] download in
            MainActor.assumeIsolated { self?.updateDownload(download) }
        }
    }

    func page(for tab: BrowserTab, profile: Profile) -> BrowserPage {
        if let page = pages[tab.id] { return page }
        let usesMediaEngine = mediaEngine != nil && ProtectedMedia.needsSystemEngine(tab.url)
        let page = (usesMediaEngine ? mediaEngine! : engine).makePage(url: tab.url, profile: profile)
        page.delegate = self
        pages[tab.id] = page
        tabIDs[ObjectIdentifier(page)] = tab.id
        pageProfiles[tab.id] = profile.id
        profilesByTab[tab.id] = profile
        if usesMediaEngine { mediaPages.insert(tab.id) }
        if profile.isPrivate == true { privatePages.insert(tab.id) }
        return page
    }

    func existingPage(for id: BrowserTab.ID?) -> BrowserPage? {
        id.flatMap { pages[$0] }
    }

    // MARK: Extensions

    var supportsExtensions: Bool { engine.supportsExtensions }

    func extensions(for profile: Profile) -> [InstalledExtension] { engine.extensions(for: profile) }

    /// A page for an extension's popup. It belongs to no tab: the caller closes it when the
    /// popup goes away, and links it opens become tabs.
    func makeExtensionPopup(_ url: URL, profile: Profile) -> BrowserPage {
        let page = engine.makePage(url: url, profile: profile)
        page.delegate = self
        return page
    }

    /// Web views take drops themselves, which would hide the page area's own drop target while
    /// a sidebar item is dragged onto it. They stop taking drops until the mouse is released.
    func suspendPageDrops() {
        guard suspendedDropTypes.isEmpty else { return }
        func suspend(_ view: NSView) {
            if !view.registeredDraggedTypes.isEmpty {
                suspendedDropTypes.append((view, view.registeredDraggedTypes))
                view.unregisterDraggedTypes()
            }
            view.subviews.forEach(suspend)
        }
        pages.values.forEach { suspend($0.view) }
        Task {
            while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: .milliseconds(200)) }
            for (view, types) in suspendedDropTypes { view.registerForDraggedTypes(types) }
            suspendedDropTypes = []
        }
    }

    /// Deletes a removed profile's data from disk, and its history.
    func removeData(for profile: Profile) {
        engine.removeData(for: profile)
        mediaEngine?.removeData(for: profile)
        history.removeProfile(profile.id)
    }

    func activate(_ store: BrowserStore) {
        self.store = store
        activeStoreID = ObjectIdentifier(store)
    }

    // MARK: Find

    func openFind(in id: BrowserTab.ID) {
        if let current = findTabID, current != id { existingPage(for: current)?.stopFinding() }
        if findTabID == id { findFocusRequest += 1; return }
        findTabID = id
        findResult = nil
    }

    func find(_ text: String, forward: Bool = true, findNext: Bool = false) {
        lastFindText = text
        guard let page = existingPage(for: findTabID) else { return }
        if text.isEmpty {
            page.stopFinding()
            findResult = nil
        } else {
            page.find(text, forward: forward, findNext: findNext)
        }
    }

    func closeFind() {
        existingPage(for: findTabID)?.stopFinding()
        findTabID = nil
        findResult = nil
    }

    // MARK: Zoom

    func zoom(_ id: BrowserTab.ID?, _ change: (Double) -> Double) {
        guard let id, let page = existingPage(for: id) else { return }
        let factor = change(page.zoomFactor)
        page.zoomFactor = factor
        if let host = store?.spaces.lazy.compactMap({ $0.pageTab(id) }).first?.url.host() {
            siteZoom[host] = abs(factor - 1) < 0.001 ? nil : factor
            UserDefaults.standard.set(siteZoom, forKey: "SiteZoom")
        }
        zoomNotice = (id, factor, (zoomNotice?.count ?? 0) + 1)
        let count = zoomNotice?.count
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if zoomNotice?.count == count { zoomNotice = nil }
        }
    }

    /// A page arriving on a site uses the zoom picked for it before.
    private func applySiteZoom(_ page: BrowserPage, tab id: BrowserTab.ID, url: URL?) {
        guard let host = url?.host(), zoomedHosts[id] != host else { return }
        zoomedHosts[id] = host
        let factor = siteZoom[host] ?? 1
        if abs(page.zoomFactor - factor) > 0.001 { page.zoomFactor = factor }
    }

    // MARK: Full screen

    func exitFullscreen() {
        existingPage(for: fullscreenTabID)?.exitFullscreen()
    }

    // MARK: Site settings and browsing data

    var supportsSiteSettings: Bool { engine.supportsSiteSettings }
    func setBlocksThirdPartyCookies(_ block: Bool) { engine.setBlocksThirdPartyCookies(block) }
    func siteExceptions(for profile: Profile) -> [SiteException] { engine.siteExceptions(for: profile) }
    func resetSiteException(_ exception: SiteException, for profile: Profile) {
        engine.resetSiteException(exception, for: profile)
    }
    var browsingDataClearedAtLaunch: BrowsingData { engine.browsingDataClearedAtLaunch }

    /// Clears a profile's data. Its open pages reload afterwards, so they don't keep showing
    /// what was signed in.
    func clearBrowsingData(_ data: BrowsingData, for profile: Profile, completion: @escaping @MainActor () -> Void) {
        mediaEngine?.clearBrowsingData(data, for: profile) {}
        engine.clearBrowsingData(data, for: profile) { [weak self] in
            if let self, let store = self.store, data.contains(.cookies) {
                for space in store.spaces(using: profile.id) {
                    for id in space.pageIDs { self.pages[id]?.reload() }
                }
            }
            completion()
        }
    }

    func close(_ id: BrowserTab.ID) {
        if findTabID == id { findTabID = nil; findResult = nil }
        if fullscreenTabID == id { fullscreenTabID = nil }
        pageProfiles[id] = nil
        profilesByTab[id] = nil
        mediaPages.remove(id)
        crashedTabs[id] = nil
        recordedURLs[id] = nil
        liveTitles[id] = nil
        liveURLs[id] = nil
        loadingProgress[id] = nil
        zoomedHosts[id] = nil
        privatePages.remove(id)
        credentialRequests.removeValue(forKey: id)?.respond(nil, nil)
        certificateWarnings.removeValue(forKey: id)?.respond(false)
        guard let page = pages.removeValue(forKey: id) else { return }
        tabIDs[ObjectIdentifier(page)] = nil
        page.close()
    }

    /// Closes pages for tabs untouched for `idle` seconds, except the visible ones.
    func sleepIdle(spaces: [Space], visible: Set<BrowserTab.ID>, idle: TimeInterval) {
        let cutoff = Date.now.addingTimeInterval(-idle)
        for tab in spaces.flatMap(\.tabs) where tab.lastActive < cutoff && !visible.contains(tab.id) {
            close(tab.id)
        }
    }

    // MARK: Downloads

    nonisolated static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    var activeDownloads: [Download] { downloads.filter { $0.state == .inProgress } }

    func cancelDownload(_ id: Download.ID) { engine.cancelDownload(id) }

    /// Removes finished downloads from the list. Their files stay.
    func clearFinishedDownloads() {
        downloads.removeAll { $0.state != .inProgress }
    }

    private func updateDownload(_ download: Download) {
        if let i = downloads.firstIndex(where: { $0.id == download.id }) {
            let wasActive = downloads[i].state == .inProgress
            var updated = download
            updated.startedAt = downloads[i].startedAt
            downloads[i] = updated
            if wasActive, download.state == .complete, let file = download.fileURL {
                // Bounces the Downloads stack in the Dock, as Safari and Chrome do.
                DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
            }
        } else {
            downloads.insert(download, at: 0)
            if download.state == .inProgress { downloadStartCount += 1 }
        }
    }

    // MARK: BrowserPageDelegate

    func page(_ page: BrowserPage, didChangeTitle title: String?, url: URL?) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { return }
        store?.updateTab(id, title: title, url: url)
        if let title { liveTitles[id] = title }
        if let url { liveURLs[id] = url }
        recordHistory(for: id, title: title, url: url)
        applySiteZoom(page, tab: id, url: url)
        revision += 1
        if let url, mediaEngine != nil, !mediaPages.contains(id), ProtectedMedia.needsSystemEngine(url) {
            // Not from inside the engine's own callback.
            Task { @MainActor in self.moveToMediaEngine(id, url: url) }
        }
    }

    /// A tab that went to a streaming site carries on in WebKit. It stays there afterwards,
    /// so sign-in pages and the site's own links keep the same cookies.
    private func moveToMediaEngine(_ id: BrowserTab.ID, url: URL) {
        guard let mediaEngine, let old = pages[id], let profile = profilesByTab[id], !mediaPages.contains(id) else { return }
        tabIDs[ObjectIdentifier(old)] = nil
        old.close()
        let page = mediaEngine.makePage(url: url, profile: profile)
        page.delegate = self
        pages[id] = page
        tabIDs[ObjectIdentifier(page)] = id
        mediaPages.insert(id)
        loadingProgress[id] = nil
        engineSwitches += 1
    }

    /// Whether a tab's page runs on macOS's WebKit for protected video, for page info.
    func usesMediaEngine(_ id: BrowserTab.ID) -> Bool { mediaPages.contains(id) }

    func page(_ page: BrowserPage, didCrashOutOfMemory outOfMemory: Bool) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { return }
        crashedTabs[id] = outOfMemory
        loadingProgress[id] = nil
        if fullscreenTabID == id { fullscreenTabID = nil }
    }

    func reloadCrashedTab(_ id: BrowserTab.ID) {
        crashedTabs[id] = nil
        pages[id]?.reload()
    }

    /// A new address is a visit; a new title for the same address only renames it.
    private func recordHistory(for id: BrowserTab.ID, title: String?, url: URL?) {
        guard let url, let profileID = pageProfiles[id], !privatePages.contains(id) else { return }
        if recordedURLs[id] == url {
            if let title { history.updateTitle(title, for: url, profileID: profileID) }
        } else {
            recordedURLs[id] = url
            history.recordVisit(to: url, title: title, profileID: profileID)
        }
    }

    func page(_ page: BrowserPage, requestsNewTab url: URL) {
        guard let store else { return }
        // Links from a favorite to another site open in a peek card, as in Arc, so the
        // favorite's own page stays put and the tab list doesn't fill up.
        if let id = tabIDs[ObjectIdentifier(page)],
           let favorite = store.spaces.lazy.compactMap({ $0.favorite(withPage: id) }).first,
           url.host() != favorite.url.host(), store.peekTab == nil {
            store.peek(url)
            return
        }
        store.openTab(url)
    }

    /// The live title and address of a page, including tabs the store doesn't track, like a peek.
    func currentPage(of id: BrowserTab.ID) -> (title: String?, url: URL?) {
        (liveTitles[id], liveURLs[id])
    }

    func page(_ page: BrowserPage, requestsPermission request: PermissionRequest) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { request.respond(false); return }
        permissionRequests.append(TabPermissionRequest(tabID: id, request: request))
        usedPermissions[request.host, default: []].formUnion(request.permissions)
    }

    func page(_ page: BrowserPage, dismissedPermissionRequest id: UInt64) {
        permissionRequests.removeAll { $0.request.id == id }
    }

    func page(_ page: BrowserPage, didFindMatches count: Int, active: Int) {
        guard let id = tabIDs[ObjectIdentifier(page)], id == findTabID else { return }
        findResult = (count, active)
    }

    func page(_ page: BrowserPage, didChangeLoading isLoading: Bool, progress: Double) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { return }
        let wasLoading = loadingProgress[id] != nil
        if isLoading, crashedTabs[id] != nil { crashedTabs[id] = nil }
        loadingProgress[id] = isLoading ? max(progress, loadingProgress[id] ?? 0) : nil
        // Toolbar buttons only care about starting and stopping, not each progress step.
        if wasLoading != isLoading { revision += 1 }
    }

    func page(_ page: BrowserPage, didChangeFavicon png: Data?) {
        guard let id = tabIDs[ObjectIdentifier(page)], !privatePages.contains(id), let png,
              let url = store?.library.spaces.lazy.compactMap({ $0.pageTab(id) }).first?.url else { return }
        FaviconCache.shared.store(png, for: url)
    }

    func page(_ page: BrowserPage, requestsCredentials request: CredentialRequest) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { request.respond(nil, nil); return }
        credentialRequests.removeValue(forKey: id)?.respond(nil, nil)
        credentialRequests[id] = request
    }

    func page(_ page: BrowserPage, hitCertificateError warning: CertificateWarning) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { warning.respond(false); return }
        certificateWarnings.removeValue(forKey: id)?.respond(false)
        certificateWarnings[id] = warning
    }

    func answerCredentials(for id: BrowserTab.ID, user: String?, password: String?) {
        credentialRequests.removeValue(forKey: id)?.respond(user, password)
    }

    /// Going back leaves the untrusted site; visiting anyway loads it.
    func answerCertificateWarning(for id: BrowserTab.ID, proceed: Bool) {
        certificateWarnings.removeValue(forKey: id)?.respond(proceed)
        if !proceed, let page = pages[id], page.canGoBack { page.goBack() }
    }

    func page(_ page: BrowserPage, didChangeFullscreen fullscreen: Bool) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { return }
        if fullscreen {
            fullscreenTabID = id
        } else if fullscreenTabID == id {
            fullscreenTabID = nil
        }
    }

    /// Answers a prompt shown for `request`.
    func answer(_ request: TabPermissionRequest, allow: Bool) {
        permissionRequests.removeAll { $0.id == request.id }
        request.request.respond(allow)
    }

    /// Mutes or unmutes every open page of a site, after its sound setting changes.
    func setSiteMuted(_ muted: Bool, host: String) {
        guard let store else { return }
        for tab in store.spaces.flatMap(\.tabs) where tab.url.host() == host {
            pages[tab.id]?.setAudioMuted(muted)
        }
    }
}

/// A permission prompt and the tab it came from.
struct TabPermissionRequest: Identifiable {
    let tabID: BrowserTab.ID
    let request: PermissionRequest
    var id: UInt64 { request.id }
}
