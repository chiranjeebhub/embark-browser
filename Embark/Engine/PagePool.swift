import AppKit
import Observation

/// Keeps one live page per open tab so switching is instant, and puts tabs nobody has
/// looked at for a while to sleep to keep memory low. A sleeping tab reloads when shown.
@MainActor
@Observable
final class PagePool: BrowserPageDelegate {
    @ObservationIgnored private let engine: BrowserEngine
    @ObservationIgnored private var pages: [BrowserTab.ID: BrowserPage] = [:]
    @ObservationIgnored private var tabIDs: [ObjectIdentifier: BrowserTab.ID] = [:]
    @ObservationIgnored weak var store: BrowserStore?
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
    /// The tab showing a video (or other element) full screen.
    private(set) var fullscreenTabID: BrowserTab.ID?

    /// Downloads this session, newest first.
    private(set) var downloads: [Download] = []
    /// Bumped when a download starts, so the sidebar can show the list.
    private(set) var downloadStartCount = 0

    init(engine: BrowserEngine = Engines.make()) {
        self.engine = engine
        engine.observeDownloads { name in
            Download.destination(for: name, in: Self.downloadsFolder)
        } update: { [weak self] download in
            MainActor.assumeIsolated { self?.updateDownload(download) }
        }
    }

    func page(for tab: BrowserTab, profile: Profile) -> BrowserPage {
        if let page = pages[tab.id] { return page }
        let page = engine.makePage(url: tab.url, profile: profile)
        page.delegate = self
        pages[tab.id] = page
        tabIDs[ObjectIdentifier(page)] = tab.id
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

    /// Deletes a removed profile's data from disk.
    func removeData(for profile: Profile) { engine.removeData(for: profile) }

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

    // MARK: Full screen

    func exitFullscreen() {
        existingPage(for: fullscreenTabID)?.exitFullscreen()
    }

    func close(_ id: BrowserTab.ID) {
        if findTabID == id { findTabID = nil; findResult = nil }
        if fullscreenTabID == id { fullscreenTabID = nil }
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
        revision += 1
    }

    func page(_ page: BrowserPage, requestsNewTab url: URL) {
        store?.openTab(url)
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
