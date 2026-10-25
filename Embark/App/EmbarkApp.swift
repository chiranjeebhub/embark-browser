import SwiftUI

@main
struct EmbarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// For the History and Settings windows, which aren't tied to a browser window.
    @State private var store = BrowserStore(isWindow: false)
    @State private var pool = PagePool()

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserWindowRoot()
                .environment(pool)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { BrowserCommands(fallbackStore: store, pool: pool) }

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Chromium locks its profile folders, so a second copy of Embark can't start it. Hand
        // over to the copy that's already running instead.
        if let running = Self.otherRunningInstance() {
            running.activate()
            exit(0)
        }
        #if ENGINE_CEF
        if !EMBCEFRuntime.start(withCacheRoot: CEFEngine.cacheRoot) {
            NSLog("Embark: Chromium failed to start")
        }
        #endif
    }

    /// Another Embark from the same bundle, e.g. launched from a second copy of the app.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != me && !$0.isTerminated }
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
    @State private var store = BrowserStore.forNewWindow()

    var body: some View {
        BrowserWindow()
            .environment(store)
            .focusedSceneValue(\.browserStore, store)
            .onAppear { pool.activate(store) }
            .onChange(of: activeState) { if activeState == .key { pool.activate(store) } }
            // Named after its space in the Window menu and Mission Control.
            .navigationTitle(store.selectedSpace?.name ?? "Embark")
            .onChange(of: store.spaces.map(\.id)) {
                // Another window deleted this window's space.
                if store.selectedSpace == nil, let first = store.spaces.first { store.selectSpace(first.id) }
            }
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
            Button("New Tab") { store.isCommandBarOpen = true }
                .keyboardShortcut("t")
            Button("Open Location") { store.isCommandBarOpen = true }
                .keyboardShortcut("l")
            Button("New Folder") { store.addFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Close Tab") {
                if let id = store.selectedTab?.id { pool.close(id); store.closeTab(id) }
            }
            .keyboardShortcut("w")
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

    /// ⌘G opens the find bar with the last search if it's closed.
    private func findAgain(forward: Bool) {
        guard let id = store.selectedTab?.id else { return }
        if pool.findTabID != id { pool.openFind(in: id) }
        guard !pool.lastFindText.isEmpty else { return }
        pool.find(pool.lastFindText, forward: forward, findNext: true)
    }
}
