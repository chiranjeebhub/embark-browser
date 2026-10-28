import SwiftUI

/// Arc's mini player: what a tab off screen is playing, at the bottom of the sidebar, with
/// play/pause and track controls. Clicking it goes back to the tab; closing it pauses.
struct MiniPlayer: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        let playing = current
        ZStack {
            if let playing {
                MiniPlayerCard(tab: playing.tab, state: playing.state, open: { open(playing.tab.id, in: playing.spaceID) })
                    .id(playing.tab.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: playing?.tab.id)
    }

    /// Media in a tab that isn't on screen, with the tab and its space.
    private var current: (tab: BrowserTab, spaceID: Space.ID, state: MediaState)? {
        guard !pool.media.isEmpty else { return nil }
        var onScreen: Set<BrowserTab.ID> = []
        if let selected = store.selectedTab?.id {
            onScreen.insert(selected)
            onScreen.formUnion(store.split(containing: selected)?.tabIDs ?? [])
        }
        if let peek = store.peekTab?.id { onScreen.insert(peek) }
        let offScreen = Set(store.spaces.flatMap(\.pageIDs)).subtracting(onScreen)
        guard let id = pool.miniPlayerTab(among: offScreen), let state = pool.media[id],
              let space = store.spaces.first(where: { $0.pageTab(id) != nil }),
              let tab = space.pageTab(id) else { return nil }
        return (tab, space.id, state)
    }

    private func open(_ id: BrowserTab.ID, in spaceID: Space.ID) {
        store.selectSpace(spaceID)
        store.selectTab(id)
    }
}

private struct MiniPlayerCard: View {
    let tab: BrowserTab
    let state: MediaState
    let open: () -> Void
    @Environment(PagePool.self) private var pool
    @State private var hovering = false

    private var isMuted: Bool { pool.mutedTabs.contains(tab.id) }

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing,
                                      isActive: state.isPlaying && !isMuted)
                        .opacity(state.isPlaying ? 1 : 0.5)
                    Text(subtitle).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if state.canGoPrevious { control("backward.fill", help: "Previous") { pool.controlMedia(tab.id, .previous) } }
                control(state.isPlaying ? "pause.fill" : "play.fill", size: 15, help: state.isPlaying ? "Pause" : "Play") {
                    pool.controlMedia(tab.id, state.isPlaying ? .pause : .play)
                }
                .contentTransition(.symbolEffect(.replace))
                if state.canGoNext { control("forward.fill", help: "Next") { pool.controlMedia(tab.id, .next) } }
            }
        }
        .padding(8)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture(perform: open)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 2) {
                    if state.hasVideo && state.canPictureInPicture {
                        corner("pip.enter", help: "Picture in Picture") { pool.controlMedia(tab.id, .pictureInPicture) }
                    }
                    corner(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: isMuted ? "Unmute Tab" : "Mute Tab") {
                        pool.toggleMuted(tab.id)
                    }
                    corner("xmark", help: "Pause and Close") { pool.dismissMiniPlayer(tab.id) }
                }
                .padding(3)
                .glassEffect(.regular.interactive(), in: .capsule)
                .offset(x: 4, y: -14)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .help("Go to \(tab.title)")
        .contextMenu {
            Button("Go to Tab", action: open)
            Button(isMuted ? "Unmute Tab" : "Mute Tab") { pool.toggleMuted(tab.id) }
            Divider()
            Button("Pause and Close Player") { pool.dismissMiniPlayer(tab.id) }
        }
    }

    private var title: String { state.title.isEmpty ? tab.title : state.title }

    private var subtitle: String {
        if !state.artist.isEmpty { return state.artist }
        let host = tab.url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The track's artwork, or the site's icon on a soft tile.
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12))
            FaviconView(url: tab.url, size: 20)
            if let url = state.artwork {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func control(_ symbol: String, size: CGFloat = 12, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func corner(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The speaker on a tab playing sound. Clicking it mutes or unmutes the tab.
struct TabSpeakerButton: View {
    let tabID: BrowserTab.ID
    var size: CGFloat = 11
    @Environment(PagePool.self) private var pool

    /// Whether a tab shows the speaker: it plays sound, or it's muted with media in it.
    @MainActor static func shows(_ id: BrowserTab.ID, in pool: PagePool) -> Bool {
        guard let state = pool.media[id] else { return false }
        return state.isPlaying || pool.mutedTabs.contains(id)
    }

    var body: some View {
        let muted = pool.mutedTabs.contains(tabID)
        let playing = pool.media[tabID]?.isPlaying == true
        Button { pool.toggleMuted(tabID) } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: size, weight: .semibold))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, isActive: playing && !muted)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(muted ? .secondary : .primary)
                .frame(width: size + 9, height: size + 9)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(muted ? "Unmute Tab" : "Mute Tab")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
