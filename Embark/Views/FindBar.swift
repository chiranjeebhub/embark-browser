import SwiftUI

/// ⌘F: a small glass bar over the page's top-right corner. Return finds the next match,
/// Shift-Return the previous one, Escape closes it.
struct FindBar: View {
    @Environment(PagePool.self) private var pool
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find on Page", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { step(forward: !NSEvent.modifierFlags.contains(.shift)) }
                .frame(minWidth: 140)
            if let result = pool.findResult, !text.isEmpty {
                Text(result.count == 0 ? "No matches" : "\(result.active) of \(result.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(result.count == 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .fixedSize()
            }
            HStack(spacing: 2) {
                Button { step(forward: false) } label: { Image(systemName: "chevron.up") }
                    .help("Previous Match (⇧⌘G)")
                Button { step(forward: true) } label: { Image(systemName: "chevron.down") }
                    .help("Next Match (⌘G)")
                Button { pool.closeFind() } label: { Image(systemName: "xmark") }
                    .help("Done")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .frame(width: 340)
        .onKeyPress(.escape) { pool.closeFind(); return .handled }
        .onChange(of: text) { pool.find(text) }
        .onAppear {
            text = pool.lastFindText
            isFocused = true
        }
        .onChange(of: pool.findFocusRequest) { isFocused = true }
    }

    private func step(forward: Bool) {
        guard !text.isEmpty else { return }
        pool.find(text, forward: forward, findNext: true)
    }
}
