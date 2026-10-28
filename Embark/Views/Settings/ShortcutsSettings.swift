import SwiftUI

struct ShortcutsSettings: View {
    private static let groups: [(String, [(String, [String])])] = [
        ("Tabs", [("New tab or search", ["⌘", "T"]), ("Open location", ["⌘", "L"]), ("Close tab", ["⌘", "W"]),
                  ("Add to favorites", ["⌘", "D"]), ("New folder", ["⌥", "⌘", "N"]), ("Back", ["⌘", "["]),
                  ("Forward", ["⌘", "]"]), ("Reload", ["⌘", "R"])]),
        ("Spaces and sidebar", [("Next space", ["⌥", "⌘", "→"]), ("Previous space", ["⌥", "⌘", "←"]),
                                ("Go to space 1–9", ["⌃", "1…9"]), ("Toggle sidebar", ["⌘", "S"]),
                                ("Switch space", ["Two-finger swipe"])]),
        ("Split view", [("New split", ["⌃", "⇧", "="]), ("Previous pane", ["⌃", "⇧", "["]), ("Next pane", ["⌃", "⇧", "]"])]),
        ("Little windows", [("Open in space", ["⌘", "O"])]),
        ("Embark", [("Settings", ["⌘", ","]), ("Quit", ["⌘", "Q"])]),
    ]

    var body: some View {
        SettingsPage(pane: .shortcuts) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 36, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 4) {
                ForEach(Self.groups, id: \.0) { group in
                    SettingsSection(group.0) {
                        ForEach(group.1, id: \.0) { item in
                            HStack {
                                Text(item.0)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(item.1, id: \.self) { KeyCap(text: $0) }
                                }
                            }
                            .frame(height: 32)
                        }
                    }
                }
            }
            .id("Keyboard shortcuts")
        }
    }
}

/// One key, drawn like a key.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(.primary.opacity(0.07), in: .rect(cornerRadius: 5))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.12)).frame(height: 1).padding(.horizontal, 2)
            }
    }
}
