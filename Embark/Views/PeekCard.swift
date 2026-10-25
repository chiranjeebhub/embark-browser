import SwiftUI

/// A link opened from a favorite, in a card floating over the page (Arc's Peek). Close it to
/// go back to the favorite, or open it as a tab to keep it.
struct PeekCard: View {
    let tab: BrowserTab
    let profile: Profile
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool

    var body: some View {
        let _ = pool.revision
        let live = pool.currentPage(of: tab.id)
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: close) { Image(systemName: "xmark") }
                        .help("Close (Esc)")
                    FaviconView(url: live.url ?? tab.url, size: 14)
                    Text((live.url ?? tab.url).host() ?? live.title ?? tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.openPeekAsTab(title: live.title, url: live.url)
                    } label: {
                        Label("Open as Tab", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Keep it as a tab")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .frame(height: 34)
                PageHost(tab: tab, profile: profile)
            }
            .clipShape(.rect(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func close() {
        pool.close(tab.id)
        store.peekTab = nil
    }
}
