import AppKit
import SwiftUI

/// A space's icon: its symbol, its emoji or letters, or the first letter of its name.
struct SpaceIconView: View {
    let icon: String?
    let name: String
    var size: CGFloat = 15

    var body: some View {
        switch SpaceIcon.kind(of: icon) {
        case .symbol(let symbol):
            Image(systemName: symbol).font(.system(size: size))
        case .text(let text):
            Text(text).font(.system(size: size * 0.95, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
        case .initial:
            Text(name.prefix(1).uppercased()).font(.system(size: size, weight: .bold))
        }
    }
}

/// A profile's round badge: its first letter on its color. nil draws "new profile".
struct ProfileBadge: View {
    let profile: Profile?
    var size: CGFloat = 20

    var body: some View {
        if let profile {
            Circle()
                .fill((profile.tint ?? .blue).color.gradient)
                .frame(width: size, height: size)
                .overlay {
                    Text(profile.name.prefix(1).uppercased())
                        .font(.system(size: size * 0.48, weight: .bold))
                        .foregroundStyle(.white)
                }
        } else {
            Circle()
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                .frame(width: size, height: size)
                .overlay { Image(systemName: "plus").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.secondary) }
        }
    }
}

/// Picks a space's icon: a symbol (searchable, with ones suggested by the name), an emoji, or
/// one or two letters. Changes apply as they're picked.
struct IconPicker: View {
    @Binding var icon: String?
    let name: String
    let accent: Color
    @State private var tab = Tab.symbols
    @State private var search = ""
    @State private var typedEmoji = ""
    @State private var letters = ""

    enum Tab: String, CaseIterable {
        case symbols = "Symbols", emoji = "Emoji", letters = "Letters"
    }

    private static let available = SpaceIcon.choices.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Kind", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .symbols: symbols
            case .emoji: emoji
            case .letters: lettersField
            }

            Divider()
            HStack {
                Button("Use First Letter") { icon = nil }
                    .buttonStyle(.link)
                    .disabled(icon == nil)
                Spacer()
                SpaceIconView(icon: icon, name: name, size: 15)
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.15), in: .rect(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            switch SpaceIcon.kind(of: icon) {
            case .symbol: tab = .symbols
            case .text(let text):
                let isEmoji = text.unicodeScalars.contains { $0.value > 0x7F && $0.properties.isEmoji }
                tab = isEmoji ? .emoji : .letters
                if !isEmoji { letters = text }
            case .initial: tab = .symbols
            }
        }
    }

    @ViewBuilder private var symbols: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search symbols", text: $search).textFieldStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let suggested = SpaceIcon.suggestions(for: name).filter(Self.available.contains)
                if search.isEmpty, !suggested.isEmpty {
                    section("Suggested for “\(name)”")
                    grid(suggested)
                    section("All")
                }
                let matches = filtered
                if matches.isEmpty {
                    Text("No symbols match “\(search)”").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                grid(matches)
            }
        }
        .frame(height: 230)
    }

    private var filtered: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Self.available }
        return Self.available.filter { $0.replacingOccurrences(of: ".", with: " ").contains(query) }
    }

    private func grid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(symbols, id: \.self) { symbol in
                cell(selected: icon == symbol) { icon = symbol } label: { Image(systemName: symbol).font(.system(size: 14)) }
                    .help(symbol)
            }
        }
    }

    @ViewBuilder private var emoji: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(SpaceIcon.emoji, id: \.self) { emoji in
                let value = SpaceIcon.text(emoji)
                cell(selected: icon == value) { icon = value } label: { Text(emoji).font(.system(size: 17)) }
            }
        }
        HStack(spacing: 8) {
            TextField("Any other emoji", text: $typedEmoji)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let value = SpaceIcon.text(typedEmoji) { icon = value } }
            Button("Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) }
                .controlSize(.small)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder private var lettersField: some View {
        Text("One or two letters").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        TextField(String(name.prefix(1)).uppercased(), text: $letters)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(height: 44)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
            .onChange(of: letters) { _, text in
                if text.count > 2 { letters = String(text.prefix(2)) }
                icon = SpaceIcon.text(letters)
            }
        Text("Leave it empty to use the first letter of the space's name.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func cell(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background(selected ? AnyShapeStyle(accent) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
