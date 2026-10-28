import SwiftUI

@main
struct EmbarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// For the History and Settings windows, which aren't tied to a browser window.
    @State private var store = BrowserStore(isWindow: false)
    @State private var pool = PagePool()

    init() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.showsAddressPill: true,
            PreferenceKey.peeksAtEdge: true,
            PreferenceKey.opensLinksInLittleWindow: true,
        ])
    }

    var body: some Scene {
        WindowGroup(id: "browser") {
            // Links from other apps open in the browser window that was in front last.
            BrowserWindowRoot { store, openWindow in
                appDelegate.openWindow = openWindow
                appDelegate.store = store
            }
                .environment(pool)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { BrowserCommands(fallbackStore: store, pool: pool) }

        WindowGroup("Private Window", id: "private") {
            BrowserWindowRoot(isPrivate: true)
                .environment(pool)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        WindowGroup("Little Window", id: "little", for: LittleWindowItem.self) { $item in
            if let item {
                LittleWindow(item: item)
                    .environment(store)
                    .environment(pool)
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 640)

        Window("History", id: "history") {
            HistoryView()
                .environment(store)
                .environment(pool)
        }
        .defaultSize(width: 640, height: 560)

        Settings {
            SettingsView()
                .environment(store)
                .environment(pool)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Links from other apps open here once the window is up; until then they wait.
    weak var store: BrowserStore? { didSet { openPendingURLs() } }
    /// For opening Little windows, which only SwiftUI can do.
    var openWindow: OpenWindowAction?
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Chromium locks its profile folders, so a second copy of Embark can't start it. Hand
        // over to the copy that's already running instead.
        if let running = Self.otherRunningInstance() {
            running.activate()
            exit(0)
        }
        // Links clicked in other apps while Embark is the default browser. Handled here rather
        // than by SwiftUI, which would open a new window for each.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        #if ENGINE_CEF
        CEFEngine.clearDataBeforeLaunch()
        if !EMBCEFRuntime.start(withCacheRoot: CEFEngine.cacheRoot) {
            NSLog("Embark: Chromium failed to start")
        }
        EMBCEFRuntime.setBlocksThirdPartyCookies(UserDefaults.standard.bool(forKey: PreferenceKey.blocksThirdPartyCookies))
        #endif
    }

    /// Another Embark from the same bundle, e.g. launched from a second copy of the app.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        pendingURLs.append(url)
        openPendingURLs()
    }

    private func openPendingURLs() {
        guard let store, !pendingURLs.isEmpty else { return }
        store.isCreatingSpace = false
        let littleWindows = UserDefaults.standard.bool(forKey: PreferenceKey.opensLinksInLittleWindow)
        for url in pendingURLs {
            // A space with that site as a favorite gets it; otherwise it opens in a Little
            // window, or in the front window's space when those are turned off.
            if let spaceID = LinkRouting.space(for: url, in: store.spaces) {
                store.selectSpace(spaceID)
                store.openTab(url)
            } else if littleWindows, let openWindow, let spaceID = store.selectedSpaceID {
                let tab = BrowserTab(title: url.host() ?? url.absoluteString, url: url)
                openWindow(id: "little", value: LittleWindowItem(tab: tab, spaceID: spaceID))
            } else {
                store.openTab(url)
            }
        }
        pendingURLs = []
        NSApp.activate()
    }

    #if ENGINE_CEF
    private var isQuitting = false

    /// CEF must close every browser before it shuts down, so the first quit closes them and
    /// quits again once they are gone. If one never reports closing, quit anyway after a few
    /// seconds rather than leave the app impossible to quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard EMBCEFRuntime.hasOpenBrowsers, !isQuitting else { return .terminateNow }
        isQuitting = true
        EMBCEFRuntime.closeAllBrowsers { sender.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { sender.terminate(nil) }
        return .terminateCancel
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        #if ENGINE_CEF
        // CefShutdown stops the process on a check if a browser is still open.
        if !EMBCEFRuntime.hasOpenBrowsers { EMBCEFRuntime.shutdown() }
        #endif
    }
}

/// One browser window, with its own selected space, sidebar and command bar.
struct BrowserWindowRoot: View {
    @Environment(PagePool.self) private var pool
    @Environment(\.controlActiveState) private var activeState
    @State private var store: BrowserStore
    @Environment(\.openWindow) private var openWindow
    /// Called when the window comes to the front.
    private let onActivate: (BrowserStore, OpenWindowAction) -> Void

    init(isPrivate: Bool = false, onActivate: @escaping (BrowserStore, OpenWindowAction) -> Void = { _, _ in }) {
        _store = State(initialValue: isPrivate ? .privateWindow() : .forNewWindow())
        self.onActivate = onActivate
    }

    var body: some View {
        BrowserWindow()
            .environment(store)
            .focusedSceneValue(\.browserStore, store)
            .onAppear(perform: activate)
            .onChange(of: activeState) { if activeState == .key { activate() } }
            // Named after its space in the Window menu and Mission Control.
            .navigationTitle(store.isPrivate ? "Private Window" : store.selectedSpace?.name ?? "Embark")
            .onDisappear {
                // A private window's pages and in-memory data go with it.
                guard store.isPrivate else { return }
                for tab in store.spaces.flatMap({ $0.tabs + $0.favorites.compactMap(\.tab) }) { pool.close(tab.id) }
                for profile in store.profiles { pool.removeData(for: profile) }
            }
            .onChange(of: store.spaces.map(\.id)) {
                // Another window deleted this window's space.
                if store.selectedSpace == nil, let first = store.spaces.first { store.selectSpace(first.id) }
            }
    }
}

extension BrowserWindowRoot {
    private func activate() {
        pool.activate(store)
        onActivate(store, openWindow)
    }
}

extension FocusedValues {
    @Entry var browserStore: BrowserStore?
}

struct BrowserCommands: Commands {
    let fallbackStore: BrowserStore
    let pool: PagePool
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.browserStore) private var focusedStore

    /// The browser window in front.
    private var store: BrowserStore { focusedStore ?? pool.store ?? fallbackStore }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n")
            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Tab") { store.isCommandBarOpen = true }
                .keyboardShortcut("t")
            Button("Open Location") { store.isCommandBarOpen = true }
                .keyboardShortcut("l")
            Button("New Folder") { store.addFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Close Tab") {
                // In a Little, History or Settings window, ⌘W closes the window instead.
                if focusedStore == nil, let window = NSApp.keyWindow {
                    window.performClose(nil)
                } else if let id = store.selectedTab?.id {
                    pool.close(id)
                    store.closeTab(id)
                }
            }
            .keyboardShortcut("w")
            Button("Reopen Closed Tab") { store.reopenLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(store.selectedSpace?.recentlyClosed?.isEmpty ?? true)
            Menu("Recently Closed") {
                ForEach((store.selectedSpace?.recentlyClosed ?? []).suffix(20).reversed()) { tab in
                    Button(tab.title.isEmpty ? (tab.url.host() ?? "Untitled") : tab.title) { store.reopenClosedTab(tab.id) }
                }
            }
            .disabled(store.selectedSpace?.recentlyClosed?.isEmpty ?? true)
            Divider()
            Button("Print…") { selectedPage?.print() }
                .keyboardShortcut("p")
                .disabled(selectedPage == nil)
        }
        CommandGroup(after: .toolbar) {
            // ⌘= rather than ⌘+, so it works without Shift, as in Chrome.
            Button("Zoom In") { pool.zoom(store.selectedTab?.id, Zoom.zoomedIn) }
                .keyboardShortcut("=")
            Button("Zoom Out") { pool.zoom(store.selectedTab?.id, Zoom.zoomedOut) }
                .keyboardShortcut("-")
            Button("Actual Size") { pool.zoom(store.selectedTab?.id) { _ in 1 } }
                .keyboardShortcut("0")
            Divider()
            Button("Developer Tools") { selectedPage?.showDevTools() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(selectedPage == nil)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { if let id = store.selectedTab?.id { pool.openFind(in: id) } }
                .keyboardShortcut("f")
            Button("Find Next") { findAgain(forward: true) }
                .keyboardShortcut("g")
            Button("Find Previous") { findAgain(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandMenu("Tab") {
            Button("Back") { pool.existingPage(for: store.selectedTab?.id)?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { pool.existingPage(for: store.selectedTab?.id)?.goForward() }
                .keyboardShortcut("]")
            Button("Reload") { pool.existingPage(for: store.selectedTab?.id)?.reload() }
                .keyboardShortcut("r")
            Button("Stop") { selectedPage?.stopLoading() }
                .keyboardShortcut(".")
            Button("Copy URL") {
                guard let url = store.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Next Tab") { store.selectTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { store.selectTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Last Tab" : "Tab \(number)") { store.selectTab(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Divider()
            Button("Add to Favorites") { if let tab = store.selectedTab { store.addFavorite(from: tab) } }
                .keyboardShortcut("d")
            Button("New Split") { store.startNewSplit() }
                .keyboardShortcut("=", modifiers: [.control, .shift])
            Button("Previous Pane") { store.focusPane(offset: -1) }
                .keyboardShortcut("[", modifiers: [.control, .shift])
            Button("Next Pane") { store.focusPane(offset: 1) }
                .keyboardShortcut("]", modifiers: [.control, .shift])
        }
        CommandMenu("History") {
            Button("Show All History") { openWindow(id: "history") }
                .keyboardShortcut("y")
        }
        CommandMenu("Spaces") {
            Button("Next Space") { store.selectSpace(offset: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Space") { store.selectSpace(offset: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            ForEach(Array(store.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button(space.name) { store.selectSpace(space.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
        CommandGroup(after: .sidebar) {
            // ⌘S also toggles it; see BrowserWindow.
            Button("Toggle Sidebar") {
                withAnimation(.sidebar) { store.isSidebarVisible.toggle() }
            }
            .keyboardShortcut("b")
        }
    }

    private var selectedPage: BrowserPage? { pool.existingPage(for: store.selectedTab?.id) }

    /// ⌘G opens the find bar with the last search if it's closed.
    private func findAgain(forward: Bool) {
        guard let id = store.selectedTab?.id else { return }
        if pool.findTabID != id { pool.openFind(in: id) }
        guard !pool.lastFindText.isEmpty else { return }
        pool.find(pool.lastFindText, forward: forward, findNext: true)
    }
}
