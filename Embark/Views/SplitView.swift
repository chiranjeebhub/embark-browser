import SwiftUI

/// A split's panes, side by side or stacked, each its own rounded page with a gap between
/// them. Drag a gap to resize; double-click it to even the sizes out.
struct SplitPanes: View {
    let split: Split
    let space: Space
    let profile: Profile
    @Environment(BrowserStore.self) private var store
    /// Pane sizes while a divider is being dragged; saved to the store when the drag ends.
    @State private var liveFractions: [Double]?
    @State private var dragStartFractions: [Double]?

    static let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let fractions = liveFractions ?? split.fractions
            let length = (split.isVertical ? geo.size.height : geo.size.width) - Self.gap * CGFloat(split.tabIDs.count - 1)
            let layout = split.isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(Array(split.tabIDs.enumerated()), id: \.element) { index, tabID in
                    if let tab = space.tabs.first(where: { $0.id == tabID }) {
                        SplitPane(tab: tab, profile: profile, isActive: tabID == space.selectedTabID)
                            .frame(width: split.isVertical ? nil : length * fractions[index],
                                   height: split.isVertical ? length * fractions[index] : nil)
                    }
                    if index < split.tabIDs.count - 1 {
                        divider(after: index, length: length)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: split.tabIDs)
    }

    private func divider(after index: Int, length: CGFloat) -> some View {
        Color.clear
            .frame(width: split.isVertical ? nil : Self.gap, height: split.isVertical ? Self.gap : nil)
            .contentShape(.rect)
            .onHover { hovering in
                if hovering {
                    (split.isVertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartFractions ?? split.fractions
                        dragStartFractions = start
                        let moved = Double((split.isVertical ? value.translation.height : value.translation.width) / max(length, 1))
                        let minimum = 0.12
                        let pair = start[index] + start[index + 1]
                        let first = min(max(start[index] + moved, minimum), pair - minimum)
                        var fractions = start
                        fractions[index] = first
                        fractions[index + 1] = pair - first
                        liveFractions = fractions
                    }
                    .onEnded { _ in
                        if let liveFractions { store.setFractions(liveFractions, for: split.id) }
                        liveFractions = nil
                        dragStartFractions = nil
                    }
            )
            .onTapGesture(count: 2) { withAnimation(.snappy(duration: 0.2)) { store.evenOutSplit(split.id) } }
    }
}

/// One page of a split: clicking into it makes it the active pane, which gets a ring; its
/// top edge reveals close, move and separate on hover.
private struct SplitPane: View {
    let tab: BrowserTab
    let profile: Profile
    let isActive: Bool
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var showsControls = false

    var body: some View {
        PageHost(tab: tab, profile: profile) { if !isActive { store.selectTab(tab.id) } }
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.white.opacity(0.6) : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Color.clear.frame(height: 14).contentShape(.rect)
                    if showsControls {
                        HStack(spacing: 2) {
                            control("xmark", help: "Close Pane") { pool.close(tab.id); store.closeTab(tab.id) }
                            control("arrow.left.arrow.right", help: "Move Pane") { store.movePane(tab.id) }
                            control("rectangle.portrait.and.arrow.right", help: "Separate") { store.removeFromSplit(tab.id) }
                        }
                        .padding(3)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { showsControls = hovering } }
            }
            .animation(.snappy(duration: 0.15), value: isActive)
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Where a tab dropped on the page would go: a half of the page, shown as a preview.
enum PageDropZone {
    case leading, trailing, top, bottom

    var isVertical: Bool { self == .top || self == .bottom }
    var isBefore: Bool { self == .leading || self == .top }

    /// Left or right half, or top or bottom when the pointer is near those edges.
    init(location: CGPoint, in size: CGSize) {
        let x = location.x / max(size.width, 1), y = location.y / max(size.height, 1)
        if min(y, 1 - y) < 0.22 && min(y, 1 - y) < min(x, 1 - x) {
            self = y < 0.5 ? .top : .bottom
        } else {
            self = x < 0.5 ? .leading : .trailing
        }
    }

    /// The preview rectangle within a page of `size`.
    func rect(in size: CGSize) -> CGRect {
        switch self {
        case .leading: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
        case .trailing: CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
        case .top: CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
        case .bottom: CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
        }
    }
}
