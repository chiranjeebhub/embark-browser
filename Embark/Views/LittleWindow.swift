import SwiftUI

/// What a Little window shows: a page that isn't in any space yet, and the space it opens into.
struct LittleWindowItem: Codable, Hashable {
    var tab: BrowserTab
    var spaceID: Space.ID
}

/// Arc's Little Arc: a small window for a link opened from another app. Glance at it and close
/// it, or move it into a space with Open in Space (⌘O), page and all.
struct LittleWindow: View {
    let item: LittleWindowItem
    /// The app-level store, which shares spaces and profiles with every window.
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var isMoving = false

    var body: some View {
        let _ = pool.revision
        let live = pool.currentPage(of: item.tab.id)
        let space = store.spaces.first { $0.id == item.spaceID } ?? store.selectedSpace
        let theme = space?.resolvedTheme ?? SpaceTheme(tint: .graphite)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Room for the traffic lights.
                Spacer().frame(width: 64)
                FaviconView(url: live.url ?? item.tab.url, size: 14)
                Text((live.url ?? item.tab.url).host() ?? live.title ?? item.tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if let space {
                    Button { moveIntoSpace(space.id, title: live.title, url: live.url) } label: {
                        Label("Open in \(space.name)", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("o")
                    .help("Move this page into the \(space.name) space")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            if let space, let profile = store.profile(for: space), !isMoving {
                PageHost(tab: item.tab, profile: profile)
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding([.horizontal, .bottom], 6)
            } else {
                Color.clear
            }
        }
        .background { ThemeBackground(theme: theme).ignoresSafeArea() }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(live.title ?? item.tab.title)
        .onDisappear {
            // Closed without moving it: the page goes with the window.
            if !isMoving { pool.close(item.tab.id) }
        }
    }

    private func moveIntoSpace(_ spaceID: Space.ID, title: String?, url: URL?) {
        var tab = item.tab
        if let title, !title.isEmpty { tab.title = title }
        if let url { tab.url = url }
        isMoving = true
        // Free the page's view now, so the browser window can show it straight away.
        pool.existingPage(for: tab.id)?.view.removeFromSuperview()
        if let target = pool.store, !target.isPrivate {
            target.adoptTab(tab, into: spaceID)
            dismiss()
        } else {
            // No browser window is open: open one on that space.
            store.adoptTab(tab, into: spaceID)
            dismiss()
            openWindow(id: "browser")
        }
        NSApp.activate()
    }
}
