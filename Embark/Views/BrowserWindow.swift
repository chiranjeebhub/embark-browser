import SwiftUI

/// The whole window is tinted by the active space; the sidebar sits directly on that tint
/// and the page floats beside it as a single rounded surface.
struct BrowserWindow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    /// With the sidebar hidden, it floats over the page while the pointer is at the left edge
    /// and slides away shortly after the pointer leaves it. Toggling it pins it open.
    @State private var isPeeking = false
    @State private var hidePeek: Task<Void, Never>?
    @State private var sidebarShortcut: Any?

    var body: some View {
        let tint = store.selectedSpace?.tint.color ?? .gray
        HStack(spacing: 0) {
            if store.isSidebarVisible {
                Sidebar()
                    .frame(width: 264)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            // The page keeps the same top edge whether or not the sidebar is shown.
            content
                .overlay {
                    if store.isCommandBarOpen {
                        CommandBar().transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .padding(.leading, store.isSidebarVisible ? 0 : 8)
        }
        .overlay(alignment: .leading) {
            if !store.isSidebarVisible { peekingSidebar(tint: tint) }
        }
        .onChange(of: store.isSidebarVisible) { hidePeek?.cancel(); isPeeking = false }
        .background(WindowButtons(isVisible: store.isSidebarVisible || isPeeking))
        .background {
            ZStack {
                Rectangle().fill(.background)
                Rectangle().fill(tint.opacity(0.16))
                Circle().fill(tint.opacity(0.35)).frame(width: 460).blur(radius: 100).offset(x: -420, y: -300)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(.smooth(duration: 0.35), value: store.selectedSpaceID)
        .animation(.snappy(duration: 0.2), value: store.isCommandBarOpen)
        .task { await sleepIdleTabs() }
        .onAppear(perform: installSidebarShortcut)
        .onDisappear { sidebarShortcut.map(NSEvent.removeMonitor); sidebarShortcut = nil }
    }

    /// A strip along the left edge; hovering it floats the sidebar over the page, which stays put.
    @ViewBuilder private func peekingSidebar(tint: Color) -> some View {
        if isPeeking {
            Sidebar()
                // Keeps the toolbar row level with the traffic lights despite the inset.
                .padding(.top, -6)
                .frame(width: 264)
                .frame(maxHeight: .infinity)
                .glassEffect(.regular.tint(tint.opacity(0.25)), in: .rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 4)
                .padding([.top, .bottom, .leading], 6)
                .onHover(perform: peek)
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            Color.clear.frame(width: 8).frame(maxHeight: .infinity).contentShape(.rect)
                .onHover { hovering in if hovering { peek(true) } }
        }
    }

    private func peek(_ show: Bool) {
        hidePeek?.cancel()
        if show {
            withAnimation(.sidebar) { isPeeking = true }
        } else {
            hidePeek = Task {
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                withAnimation(.sidebar) { isPeeking = false }
            }
        }
    }

    /// ⌘S (Arc's shortcut) toggles the sidebar too, without a second menu item for it.
    private func installSidebarShortcut() {
        guard sidebarShortcut == nil else { return }
        sidebarShortcut = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "s" else { return event }
            withAnimation(.sidebar) { store.isSidebarVisible.toggle() }
            return nil
        }
    }

    @ViewBuilder private var content: some View {
        if let space = store.selectedSpace, let profile = store.profile(for: space), let tab = store.selectedTab {
            HStack(spacing: 8) {
                PageHost(tab: tab, profile: profile)
                if let splitID = store.splitTabID, let split = space.tabs.first(where: { $0.id == splitID }) {
                    PageHost(tab: split, profile: profile)
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        } else {
            EmptySpaceView()
        }
    }

    private func sleepIdleTabs() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            let visible = Set([store.selectedTab?.id, store.splitTabID].compactMap { $0 })
            pool.sleepIdle(spaces: store.spaces, visible: visible, idle: 30 * 60)
        }
    }
}

/// Hosts the engine's view for one tab. The page itself lives in the PagePool, so it survives
/// switching tabs and spaces.
struct PageHost: NSViewRepresentable {
    let tab: BrowserTab
    let profile: Profile
    @Environment(PagePool.self) private var pool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let page = pool.page(for: tab, profile: profile)
        guard page.view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        page.view.frame = container.bounds
        page.view.autoresizingMask = [.width, .height]
        container.addSubview(page.view)
    }
}

/// Shows or hides the window's traffic lights.
private struct WindowButtons: NSViewRepresentable {
    let isVisible: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let isVisible = isVisible
        DispatchQueue.main.async {
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                view.window?.standardWindowButton(kind)?.isHidden = !isVisible
            }
        }
    }
}

struct EmptySpaceView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sailboat").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text("Nothing open in this space").font(.title3.weight(.semibold))
            Button("Open something  ⌘T") { store.isCommandBarOpen = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
