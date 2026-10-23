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

    init(engine: BrowserEngine = Engines.make()) {
        self.engine = engine
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

    func close(_ id: BrowserTab.ID) {
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

    // MARK: BrowserPageDelegate

    func page(_ page: BrowserPage, didChangeTitle title: String?, url: URL?) {
        guard let id = tabIDs[ObjectIdentifier(page)] else { return }
        store?.updateTab(id, title: title, url: url)
        revision += 1
    }

    func page(_ page: BrowserPage, requestsNewTab url: URL) {
        store?.openTab(url)
    }
}
