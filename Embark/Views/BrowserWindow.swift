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

    /// How far the peeking sidebar's card sits from the window's top, left and bottom edges.
    static let peekInset: CGFloat = 8

    var body: some View {
        // The Create a Space form previews its tint on the whole window.
        let tint = (store.draftTint ?? store.selectedSpace?.tint)?.color ?? .gray
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
        .background(WindowButtons(isVisible: store.isSidebarVisible || isPeeking,
                                  offset: isPeeking && !store.isSidebarVisible ? Self.peekInset : 0))
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
            // A card inset from the window. The sidebar inside keeps its usual margins and width,
            // so everything sits as far from the card's edges as it does from the window's when
            // pinned; the traffic lights move by the same inset (see WindowButtons).
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
                .padding([.top, .bottom, .leading], Self.peekInset)
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
        } else {
            EmptySpaceView()
        }
    }

    private func sleepIdleTabs() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            let visible = Set([store.selectedTab?.id].compactMap { $0 } + (store.split(containing: store.selectedTab?.id)?.tabIDs ?? []))
            pool.sleepIdle(spaces: store.spaces, visible: visible, idle: 30 * 60)
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
/// Shows or hides the window's traffic lights, and shifts them right and down by `offset`
/// (used to keep them inside the peeking sidebar's card).
private struct WindowButtons: NSViewRepresentable {
    let isVisible: Bool
    var offset: CGFloat = 0

    final class Coordinator {
        /// Each button's resting origin while it's shifted.
        var origins: [NSWindow.ButtonType: NSPoint] = [:]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let isVisible = isVisible, offset = offset, coordinator = context.coordinator
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.16
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    guard let button = view.window?.standardWindowButton(kind) else { continue }
                    button.isHidden = !isVisible
                    // Only touch the frame while shifted or coming back, so AppKit's own layout
                    // (window resizing, full screen) isn't overridden with a stale position.
                    guard offset != 0 || coordinator.origins[kind] != nil else { continue }
                    let origin = coordinator.origins[kind] ?? button.frame.origin
                    // The title bar isn't flipped, so moving down lowers y.
                    let flipped = button.superview?.isFlipped ?? false
                    button.animator().setFrameOrigin(NSPoint(x: origin.x + offset, y: origin.y + (flipped ? offset : -offset)))
                    coordinator.origins[kind] = offset == 0 ? nil : origin
                }
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
