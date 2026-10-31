import SwiftUI

struct AppearanceSettings: View {
    @AppStorage(PreferenceKey.sidebarSide) private var sidebarSide = SidebarSide.left
    @AppStorage(PreferenceKey.showsAddressPill) private var showsAddressPill = true
    @AppStorage(PreferenceKey.peeksAtEdge) private var peeksAtEdge = true
    @AppStorage(PreferenceKey.newSpaceTheme) private var newSpaceTheme = NewSpaceTheme.unused

    var body: some View {
        SettingsPage(pane: .appearance) {
            SettingsSection("Sidebar") {
                SettingRow("Sidebar position", detail: "On the right, the window buttons sit above the page.") {
                    HStack(spacing: 14) {
                        ForEach(SidebarSide.allCases) { side in
                            Button { withAnimation(.sidebar) { sidebarSide = side } } label: {
                                VStack(spacing: 6) {
                                    SidebarThumbnail(side: side)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 9)
                                                .strokeBorder(sidebarSide == side ? Color.accentColor : .primary.opacity(0.18),
                                                              lineWidth: sidebarSide == side ? 2.5 : 1)
                                                .padding(sidebarSide == side ? -3 : 0)
                                        }
                                    Text(side == .left ? "Left" : "Right").font(.system(size: 12))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(side == .left ? "Sidebar on the left" : "Sidebar on the right")
                            .accessibilityAddTraits(sidebarSide == side ? .isSelected : [])
                        }
                    }
                }
                SettingToggle("Show the address in the sidebar",
                              detail: "The pill above your favorites, with copy link, extensions and page info. Off, ⌘L still shows the address.",
                              isOn: $showsAddressPill)
                SettingToggle("Show the sidebar at the window edge",
                              detail: "While it’s hidden, moving the pointer to the edge slides it in.",
                              isOn: $peeksAtEdge)
            }

            SettingsSection("Spaces") {
                SettingRow("New spaces start with", detail: "You can always change it while creating the space.") {
                    Picker("New spaces start with", selection: $newSpaceTheme) {
                        ForEach(NewSpaceTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

/// A tiny window with its sidebar on one side.
private struct SidebarThumbnail: View {
    let side: SidebarSide

    var body: some View {
        HStack(spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
                if side == .left { lights }
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(.primary.opacity(0.25)).frame(height: 3) }
                Spacer()
            }
            .frame(width: 22)
            RoundedRectangle(cornerRadius: 3).fill(.background).shadow(color: .black.opacity(0.15), radius: 1)
                .padding(.top, side == .right ? 9 : 0)
        }
        .environment(\.layoutDirection, side == .left ? .leftToRight : .rightToLeft)
        .padding(5)
        .frame(width: 84, height: 54)
        .background(LinearGradient(colors: [Color(red: 0.55, green: 0.5, blue: 0.95), Color(red: 0.3, green: 0.65, blue: 0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.6),
                    in: .rect(cornerRadius: 9))
        .overlay(alignment: .topLeading) { if side == .right { lights.padding(5) } }
    }

    private var lights: some View {
        HStack(spacing: 2) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
        }
        .frame(width: 16, height: 4)
    }
}
