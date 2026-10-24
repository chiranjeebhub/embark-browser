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

struct BrowserCommands: Commands {
    let store: BrowserStore
    let pool: PagePool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
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
}
