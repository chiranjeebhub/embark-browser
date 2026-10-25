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
    /// Where a tab dragged over the page would land, for the split preview.
    @State private var pageDropZone: PageDropZone?

    @AppStorage(PreferenceKey.sidebarSide) private var sidebarSide = SidebarSide.left
    @AppStorage(PreferenceKey.peeksAtEdge) private var peeksAtEdge = true

    /// How far the peeking sidebar's card sits from the window's top, side and bottom edges.
    static let peekInset: CGFloat = 8
    /// Above the page when the sidebar is on the right: room for the traffic lights.
    static let titleStripHeight: CGFloat = 30

    private var sidebarEdge: Edge { sidebarSide == .right ? .trailing : .leading }

    private var pinnedSidebar: some View {
        Sidebar()
            .frame(width: 264)
            .transition(.move(edge: sidebarEdge).combined(with: .opacity))
    }

    var body: some View {
        // The Create a Space form previews its theme on the whole window; a swipe between
        // spaces fades toward the next space's theme as it goes.
        let theme = store.draftTheme ?? store.selectedSpace?.resolvedTheme ?? SpaceTheme(tint: .graphite)
        let neighborTheme = store.draftTheme == nil
            ? store.neighborSpace(towardProgress: store.swipeProgress)?.resolvedTheme : nil
        let tint = theme.accent
        let onRight = sidebarSide == .right
        HStack(spacing: 0) {
            if store.isSidebarVisible && !onRight { pinnedSidebar }
            // The page keeps the same top edge whether or not the sidebar is shown.
            content
                .overlay {
                    if store.isCommandBarOpen {
                        CommandBar().transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                // With the sidebar on the right, the traffic lights get a strip above the page.
                .padding(.top, onRight ? Self.titleStripHeight : 8)
                .padding(.bottom, 8)
                .padding(.leading, store.isSidebarVisible && !onRight ? 0 : 8)
                .padding(.trailing, store.isSidebarVisible && onRight ? 0 : 8)
            if store.isSidebarVisible && onRight { pinnedSidebar }
        }
        .overlay(alignment: onRight ? .trailing : .leading) {
            if !store.isSidebarVisible && peeksAtEdge { peekingSidebar(tint: tint) }
        }
        .onChange(of: store.isSidebarVisible) { hidePeek?.cancel(); isPeeking = false }
        // While peeking, the card draws its own traffic lights (see CardTrafficLights). With the
        // sidebar on the right they stay above the page.
        .background(WindowButtons(isVisible: store.isSidebarVisible || onRight))
        .background {
            ZStack {
                ThemeBackground(theme: theme)
                if let neighborTheme {
                    ThemeBackground(theme: neighborTheme).opacity(Double(abs(store.swipeProgress)))
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(colorScheme(for: theme.appearance))
        .ignoresSafeArea(.container, edges: .top)
        .animation(.smooth(duration: 0.35), value: store.selectedSpaceID)
        .animation(.snappy(duration: 0.2), value: store.isCommandBarOpen)
        .task { await sleepIdleTabs() }
        .onAppear(perform: installSidebarShortcut)
        .onDisappear { sidebarShortcut.map(NSEvent.removeMonitor); sidebarShortcut = nil }
    }

    private func colorScheme(for appearance: SpaceTheme.Appearance) -> ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    /// A strip along the sidebar's edge; hovering it floats the sidebar over the page, which stays put.
    @ViewBuilder private func peekingSidebar(tint: Color) -> some View {
        if isPeeking {
            // A card inset from the window. The sidebar inside keeps its usual margins and width,
            // so everything sits as far from the card's edges as it does from the window's when
            // pinned; its traffic lights sit at the same spot relative to the card.
            Sidebar()
                .padding(.bottom, 4)
                .frame(width: 264)
                .frame(maxHeight: .infinity)
                .background {
                    // Concentric with the ~17pt window corner at this inset.
                    Color.clear
                        .glassEffect(.regular.tint(tint.opacity(0.25)), in: .rect(cornerRadius: 17 - Self.peekInset))
                        .shadow(color: .black.opacity(0.25), radius: 16, x: 2, y: 4)
                }
                .overlay(alignment: .topLeading) {
                    // Where the system lights sit relative to the window, but relative to the card.
                    // On the right, the system's own stay above the page.
                    if sidebarSide == .left { CardTrafficLights().padding(.leading, 9).padding(.top, 9) }
                }
                .padding([.top, .bottom], Self.peekInset)
                .padding(sidebarEdge == .leading ? .leading : .trailing, Self.peekInset)
                .onHover(perform: peek)
                .transition(.move(edge: sidebarEdge).combined(with: .opacity))
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
            Group {
                if let split = store.split(containing: tab.id) {
                    SplitPanes(split: split, space: space, profile: profile)
                } else {
                    PageHost(tab: tab, profile: profile)
                }
            }
            .overlay {
                GeometryReader { geo in
                    if let zone = pageDropZone {
                        let rect = zone.rect(in: geo.size).insetBy(dx: 6, dy: 6)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.18))
                            .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .overlay(alignment: .top) {
                // Permission prompts for the pages on screen, one at a time.
                let visible = Set([tab.id] + (store.split(containing: tab.id)?.tabIDs ?? []))
                if let request = pool.permissionRequests.first(where: { visible.contains($0.tabID) }) {
                    PermissionPromptCard(request: request)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(request.id)
                }
            }
            .animation(.snappy(duration: 0.2), value: pool.permissionRequests.map(\.id))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { PageDropHandler.pageSize = $0 }
            .onDrop(of: [.utf8PlainText], delegate: PageDropHandler(store: store, zone: $pageDropZone))
            .animation(.snappy(duration: 0.2), value: pageDropZone)
            .onChange(of: store.dragEndCount) { pageDropZone = nil }
        } else {
            EmptySpaceView()
        }
    }

    private func sleepIdleTabs() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            let visible = Set([store.selectedTab?.id].compactMap { $0 } + (store.split(containing: store.selectedTab?.id)?.tabIDs ?? []))
            pool.sleepIdle(spaces: store.spaces, visible: visible, idle: 30 * 60)
            for id in store.archiveIdleTabs(keeping: visible) { pool.close(id) }
        }
    }
}

/// Hosts the engine's view for one tab. The page itself lives in the PagePool, so it survives
/// switching tabs and spaces.
struct PageHost: NSViewRepresentable {
    let tab: BrowserTab
    let profile: Profile
    /// Called when the user clicks into the page. Web views swallow clicks, so this watches
    /// the window's mouse-downs instead.
    var onClick: (() -> Void)?
    @Environment(PagePool.self) private var pool

    final class Coordinator {
        var onClick: (() -> Void)?
        var monitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak container] event in
            if let container, event.window === container.window,
               container.bounds.contains(container.convert(event.locationInWindow, from: nil)) {
                coordinator.onClick?()
            }
            return event
        }
        return container
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.monitor.map(NSEvent.removeMonitor)
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.onClick = onClick
        let page = pool.page(for: tab, profile: profile)
        guard page.view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        page.view.frame = container.bounds
        page.view.autoresizingMask = [.width, .height]
        container.addSubview(page.view)
    }
}

/// Drops a sidebar tab or favorite onto the page: it opens as a split pane on that side of the
/// current page (or split).
private struct PageDropHandler: DropDelegate {
    let store: BrowserStore
    @Binding var zone: PageDropZone?

    func validateDrop(info: DropInfo) -> Bool { SidebarDrag.current?.canSplit == true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // The drop target is the whole page area, so its size comes from the zone math below.
        zone = PageDropZone(location: info.location, in: PageDropHandler.pageSize)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { zone = nil }

    func performDrop(info: DropInfo) -> Bool {
        guard let zone, let target = store.selectedTab?.id else { return false }
        let store = store, zoneBinding = $zone
        return SidebarDrag.load(from: info) { drag in
            zoneBinding.wrappedValue = nil
            withAnimation(.snappy(duration: 0.2)) {
                switch drag {
                case .tab(let id): store.addToSplit(id, beside: target, before: zone.isBefore, isVertical: zone.isVertical)
                case .favorite(let id):
                    guard let favorite = store.selectedSpace?.favorites.first(where: { $0.id == id }) else { return }
                    let tab = store.openTab(favorite.url, title: favorite.title)
                    store.addToSplit(tab.id, beside: target, before: zone.isBefore, isVertical: zone.isVertical)
                default: break
                }
            }
            SidebarDrag.current = nil
        }
    }

    /// Updated by the page area's size reader.
    @MainActor static var pageSize = CGSize(width: 1, height: 1)
}

/// Shows or hides the window's traffic lights.
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

/// Traffic lights drawn inside the peeking sidebar's card, where the system ones can't go:
/// AppKit lays its buttons out again on resizes, focus changes and title bar updates, so moving
/// them doesn't stick (and they come apart). These match the system ones: 14pt, 23pt apart,
/// symbols on hover, grey when the window isn't active, and the same actions.
private struct CardTrafficLights: View {
    @Environment(\.controlActiveState) private var activeState
    @State private var window: NSWindow?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            light(Color(red: 1, green: 0.37, blue: 0.34), symbol: "xmark", help: "Close") { window?.performClose(nil) }
            light(Color(red: 1, green: 0.74, blue: 0.18), symbol: "minus", help: "Minimize") { window?.miniaturize(nil) }
            light(Color(red: 0.16, green: 0.78, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right", help: "Enter Full Screen") {
                window?.toggleFullScreen(nil)
            }
        }
        .onHover { hovering = $0 }
        .background(WindowReader(window: $window))
    }

    private func light(_ color: Color, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        let active = activeState != .inactive || hovering
        return Button(action: action) {
            Circle()
                .fill(active ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .overlay {
                    if hovering {
                        Image(systemName: symbol)
                            .font(.system(size: symbol.count > 6 ? 6.5 : 8, weight: .bold))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .frame(width: 14, height: 14)
        }
        .buttonStyle(PressDarkens())
        .help(help)
    }

    private struct PressDarkens: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.brightness(configuration.isPressed ? -0.15 : 0)
        }
    }
}

/// Reports the window a view is in.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if window !== view.window { window = view.window } }
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
