import SwiftUI

/// Embark ▸ Settings (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            ProfilesSettings()
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
        }
        .frame(width: 720, height: 480)
    }
}

/// Profiles on the left; the selected one's name, color and spaces on the right.
struct ProfilesSettings: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var selection: Profile.ID?
    @State private var confirmsDelete = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.profiles) { profile in
                        HStack(spacing: 10) {
                            ProfileBadge(profile: profile, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name.isEmpty ? "Untitled" : profile.name).font(.system(size: 13, weight: .medium))
                                Text(spaceCount(profile.id)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)
                HStack(spacing: 0) {
                    Button { selection = store.addProfile(name: "New Profile").id } label: {
                        Image(systemName: "plus").frame(width: 24, height: 22)
                    }
                    .help("New Profile")
                    Button { confirmsDelete = true } label: {
                        Image(systemName: "minus").frame(width: 24, height: 22)
                    }
                    .help("Delete Profile")
                    .disabled(!canDelete)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 220)

            Divider()

            if let profile = store.profiles.first(where: { $0.id == selection }) {
                detail(profile)
            } else {
                Text("Select a profile").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = store.selectedSpace?.profileID ?? store.profiles.first?.id } }
        .confirmationDialog("Delete “\(selectedProfile?.name ?? "")”?", isPresented: $confirmsDelete) {
            Button("Delete Profile", role: .destructive, action: deleteSelected)
        } message: {
            Text("Its logins, cookies, history and extensions are deleted from this Mac.")
        }
    }

    private var selectedProfile: Profile? { store.profiles.first { $0.id == selection } }

    private var canDelete: Bool {
        guard let selection else { return false }
        return store.spaces(using: selection).isEmpty
    }

    private func spaceCount(_ id: Profile.ID) -> String {
        let count = store.spaces(using: id).count
        return count == 0 ? "No spaces" : count == 1 ? "1 space" : "\(count) spaces"
    }

    private func detail(_ profile: Profile) -> some View {
        let spaces = store.spaces(using: profile.id)
        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                ProfileBadge(profile: profile, size: 64)
                    .shadow(color: (profile.tint ?? .blue).color.opacity(0.4), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Profile name", text: Binding(get: { profile.name },
                                                            set: { name in store.updateProfile(profile.id) { $0.name = name } }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(SpaceTint.allCases, id: \.self) { tint in
                        Button { store.updateProfile(profile.id) { $0.tint = tint } } label: {
                            Circle().fill(tint.color.gradient).frame(width: 20, height: 20)
                                .overlay {
                                    if profile.tint == tint {
                                        Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2).padding(-3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(tint.rawValue.capitalized)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Spaces using this profile").font(.system(size: 13, weight: .semibold))
                if spaces.isEmpty {
                    Text("None. Pick this profile when you create a space, or switch a space to it from its right-click menu.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        ForEach(spaces) { space in
                            HStack(spacing: 6) {
                                SpaceIconView(icon: space.icon, name: space.name, size: 12).foregroundStyle(space.accent)
                                Text(space.name).font(.system(size: 12))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(space.accent.opacity(0.15), in: .capsule)
                        }
                    }
                    Text("These spaces share logins, cookies, history and extensions.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                if !spaces.isEmpty {
                    Text("Move its spaces to another profile to delete it.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete Profile…", role: .destructive) { confirmsDelete = true }
                    .disabled(!spaces.isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deleteSelected() {
        guard let selection, let profile = store.deleteProfile(selection) else { return }
        pool.removeData(for: profile)
        self.selection = store.profiles.first?.id
    }
}
