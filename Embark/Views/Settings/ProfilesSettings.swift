import SwiftUI

/// Profiles as cards along the top; the selected one's name, color, spaces, extensions and
/// data below.
struct ProfilesSettings: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var selection: Profile.ID?
    @State private var confirmsDelete = false
    @State private var clearing: Profile?

    var body: some View {
        SettingsPage(pane: .profiles) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.profiles) { card($0) }
                    Button { selection = store.addProfile(name: "New Profile").id } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                            Text("New Profile").font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 104, height: 112)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .padding(.top, 20)
            .padding(.bottom, 4)

            if let profile = selectedProfile {
                detail(profile)
            }
        }
        .onAppear { if selection == nil { selection = store.selectedSpace?.profileID ?? store.profiles.first?.id } }
        .confirmationDialog("Delete “\(selectedProfile?.name ?? "")”?", isPresented: $confirmsDelete) {
            Button("Delete Profile", role: .destructive, action: deleteSelected)
        } message: {
            Text("Its logins, cookies, history and extensions are deleted from this Mac.")
        }
        .sheet(item: $clearing) { ClearDataSheet(profile: $0) }
    }

    private var selectedProfile: Profile? { store.profiles.first { $0.id == selection } }

    private func card(_ profile: Profile) -> some View {
        let isSelected = profile.id == selection
        return Button { withAnimation(.snappy(duration: 0.18)) { selection = profile.id } } label: {
            VStack(spacing: 7) {
                ProfileBadge(profile: profile, size: 44)
                    .shadow(color: (profile.tint ?? .blue).color.opacity(0.4), radius: 6, y: 3)
                Text(profile.name.isEmpty ? "Untitled" : profile.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(spaceCount(profile.id)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 104, height: 112)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder((profile.tint ?? .blue).color.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func spaceCount(_ id: Profile.ID) -> String {
        let count = store.spaces(using: id).count
        return count == 0 ? "No spaces" : count == 1 ? "1 space" : "\(count) spaces"
    }

    private func detail(_ profile: Profile) -> some View {
        let spaces = store.spaces(using: profile.id)
        return VStack(alignment: .leading, spacing: 0) {
            SettingsSection(profile.name.isEmpty ? "Profile" : profile.name) {
                SettingRow("Name and color") {
                    HStack(spacing: 14) {
                        TextField("Profile name", text: Binding(get: { profile.name },
                                                                set: { name in store.updateProfile(profile.id) { $0.name = name } }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        HStack(spacing: 7) {
                            ForEach(SpaceTint.allCases, id: \.self) { tint in
                                Button { store.updateProfile(profile.id) { $0.tint = tint } } label: {
                                    Circle().fill(tint.color.gradient).frame(width: 16, height: 16)
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
                }
                SettingRow("Used by", detail: spaces.isEmpty
                           ? "No spaces. Pick this profile when you create a space, or switch a space to it from its right-click menu."
                           : "These spaces share logins, cookies, history and extensions.") {
                    HStack(spacing: 6) {
                        ForEach(spaces) { space in
                            HStack(spacing: 5) {
                                SpaceIconView(icon: space.icon, name: space.name, size: 11).foregroundStyle(space.accent)
                                Text(space.name).font(.system(size: 12)).lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(space.accent.opacity(0.15), in: .capsule)
                        }
                    }
                }
                if pool.supportsExtensions {
                    extensions(profile, firstSpace: spaces.first)
                }
                SettingRow("Browsing data", detail: "Cookies, cached files and site storage for this profile.") {
                    Button("Clear…") { clearing = profile }
                }
            }

            HStack {
                if !spaces.isEmpty {
                    Text("Move its spaces to another profile to delete it.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete Profile…", role: .destructive) { confirmsDelete = true }
                    .disabled(!spaces.isEmpty)
            }
            .padding(.top, 18)
        }
    }

    private func extensions(_ profile: Profile, firstSpace: Space?) -> some View {
        let installed = pool.extensions(for: profile)
        let pinned = profile.pinnedExtensionIDs ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Extensions")
                Spacer()
                Button("Chrome Web Store") {
                    guard let firstSpace else { return }
                    store.selectSpace(firstSpace.id)
                    store.openTab(URL(string: "https://chromewebstore.google.com")!)
                }
                .buttonStyle(.link)
                .disabled(firstSpace == nil)
                .help(firstSpace == nil ? "Give this profile a space first" : "Opens in \(firstSpace!.name)")
            }
            if installed.isEmpty {
                Text("None yet. Extensions you add from the Chrome Web Store show up here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(installed) { item in
                HStack(spacing: 10) {
                    Group {
                        if let file = item.iconFile, let image = NSImage(contentsOf: file) {
                            Image(nsImage: image).resizable()
                        } else {
                            Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(item.name).lineLimit(1).opacity(item.isEnabled ? 1 : 0.5)
                    Spacer()
                    if pinned.contains(item.id) {
                        Text("Pinned").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 13)
        .id("Extensions")
    }

    private func deleteSelected() {
        guard let selection, let profile = store.deleteProfile(selection) else { return }
        pool.removeData(for: profile)
        self.selection = store.profiles.first?.id
    }
}

// MARK: - Clear browsing data

/// Settings ▸ Profiles ▸ Browsing data ▸ Clear…
private struct ClearDataSheet: View {
    let profile: Profile
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.dismiss) private var dismiss
    @State private var history = true
    @State private var cookies = true
    @State private var cache = true
    @State private var storage = false
    @State private var isClearing = false

    var body: some View {
        let spaces = store.spaces(using: profile.id)
        let later = chosen.intersection(pool.browsingDataClearedAtLaunch)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProfileBadge(profile: profile, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear \(profile.name)’s browsing data").font(.system(size: 15, weight: .bold))
                    Text(spaces.isEmpty ? "No space uses this profile. Other profiles aren’t touched."
                         : "Used by \(spaces.map(\.name).formatted()). Other profiles aren’t touched.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                option($history, "Recently closed tabs", "The Library’s list for these spaces")
                option($cookies, "Cookies and sign-ins", "Signs you out of most sites in this profile")
                option($cache, "Cached images and files", "Pages may load slower at first")
                option($storage, "Site storage", "Local storage, IndexedDB and offline data")
            }

            if !later.isEmpty {
                Label(later == .cache ? "Cached files are in use by open pages, so they’re removed the next time Embark starts."
                      : later == .storage ? "Site storage is in use by open pages, so it’s removed the next time Embark starts."
                      : "Cached files and site storage are in use by open pages, so they’re removed the next time Embark starts.",
                      systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clear Data", role: .destructive, action: clear)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isClearing || (chosen.isEmpty && !history))
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var chosen: BrowsingData {
        var data: BrowsingData = []
        if cookies { data.insert(.cookies) }
        if cache { data.insert(.cache) }
        if storage { data.insert(.storage) }
        return data
    }

    private func option(_ isOn: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func clear() {
        isClearing = true
        if history {
            for space in store.spaces(using: profile.id) { store.updateSpace(space.id) { $0.recentlyClosed = [] } }
        }
        guard !chosen.isEmpty else { dismiss(); return }
        pool.clearBrowsingData(chosen, for: profile) { dismiss() }
    }
}
