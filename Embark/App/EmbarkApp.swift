import SwiftUI

@main
struct EmbarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = BrowserStore()
    @State private var pool = PagePool()

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .environment(store)
                .environment(pool)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { pool.store = store }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { BrowserCommands(store: store, pool: pool) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        #if ENGINE_CEF
        if !EMBCEFRuntime.start(withCacheRoot: CEFEngine.cacheRoot) {
            NSLog("Embark: Chromium failed to start")
        }
        #endif
    }

    #if ENGINE_CEF
    /// CEF must close every browser before it shuts down, so the first quit closes them and
    /// quits again once they are gone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard EMBCEFRuntime.hasOpenBrowsers else { return .terminateNow }
        EMBCEFRuntime.closeAllBrowsers { sender.terminate(nil) }
        return .terminateCancel
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        #if ENGINE_CEF
        EMBCEFRuntime.shutdown()
        #endif
    }
}

struct BrowserCommands: Commands {
    let store: BrowserStore
    let pool: PagePool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.isCommandBarOpen = true }
                .keyboardShortcut("t")
            Button("Open Location") { store.isCommandBarOpen = true }
                .keyboardShortcut("l")
            Button("Close Tab") {
                if let id = store.selectedTab?.id { pool.close(id); store.closeTab(id) }
            }
            .keyboardShortcut("w")
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
            Button(store.splitTabID == nil ? "Split View" : "Close Split View") { toggleSplit() }
                .keyboardShortcut("=", modifiers: [.command, .shift])
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

    /// Split shows the most recently used other tab beside the current one.
    private func toggleSplit() {
        if store.splitTabID != nil { store.splitTabID = nil; return }
        guard let space = store.selectedSpace else { return }
        store.splitTabID = space.tabs
            .filter { $0.id != space.selectedTabID }
            .max { $0.lastActive < $1.lastActive }?.id
    }
}
