import SwiftUI

/// Replaces the sidebar's content while making a space. The window takes the theme as it's
/// picked, so the space is previewed for real before it exists.
struct CreateSpaceForm: View {
    @Environment(BrowserStore.self) private var store
    @State private var name = ""
    @State private var icon: String?
    /// Once an icon is picked by hand, typing the name stops suggesting one.
    @State private var pickedIcon = false
    /// nil makes a new profile; otherwise the space shares that profile's logins.
    @State private var profileID: Profile.ID?
    @State private var showsIcons = false
    @State private var showsTheme = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var theme: Binding<SpaceTheme> {
        Binding(get: { store.draftTheme ?? store.suggestedTheme() }, set: { store.draftTheme = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Button { showsIcons = true } label: {
                    IconTile(icon: icon, name: trimmedName.isEmpty ? "?" : trimmedName, accent: theme.wrappedValue.accent, size: 76)
                }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .popover(isPresented: $showsIcons, arrowEdge: .trailing) {
                    IconPicker(icon: Binding(get: { icon }, set: { icon = $0; pickedIcon = true }),
                               name: trimmedName, accent: theme.wrappedValue.accent)
                }
                TextField("Name your space", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .onSubmit(create)
                    .onChange(of: name) {
                        // Until an icon is picked, suggest one that fits the name.
                        if !pickedIcon { icon = SpaceIcon.suggestions(for: name).first }
                    }
            }
            .padding(.top, 30)

            VStack(spacing: 2) {
                Button { showsTheme.toggle() } label: {
                    HStack(spacing: 10) {
                        Text("Theme")
                        Spacer()
                        ThemeSwatch(theme: theme.wrappedValue).frame(width: 58, height: 22)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .formRow(highlighted: showsTheme)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsTheme, arrowEdge: .trailing) {
                    ThemePicker(theme: theme).padding(14)
                }

                Menu {
                    Picker("Profile", selection: $profileID) {
                        Label("New Profile", systemImage: "plus").tag(Profile.ID?.none)
                        Divider()
                        ForEach(store.profiles) { profile in Text(profile.name).tag(Profile.ID?.some(profile.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Profile")
                            Text(profileDetail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        let profile = store.profiles.first { $0.id == profileID }
                        HStack(spacing: 6) {
                            ProfileBadge(profile: profile, size: 18)
                            Text(profile?.name ?? "New").lineLimit(1)
                        }
                        .padding(.leading, 4).padding(.trailing, 9)
                        .frame(height: 26)
                        .background(.primary.opacity(0.08), in: .capsule)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .formRow(highlighted: false)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            .font(.system(size: 13))
            .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: create) {
                    Text("Create Space")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(.white.opacity(0.94), in: .rect(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.black.opacity(0.08)))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(trimmedName.isEmpty ? 0.5 : 1)
                .disabled(trimmedName.isEmpty)
                .keyboardShortcut(.defaultAction)
                Button("Cancel", action: close)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 4)
        .onAppear {
            if store.draftTheme == nil { store.draftTheme = store.suggestedTheme() }
            nameFocused = true
        }
    }

    private var profileDetail: String {
        guard let profileID else { return "Fresh logins, cookies and history" }
        let names = store.spaces(using: profileID).map(\.name)
        return names.isEmpty ? "Uses this profile's logins" : "Shares logins with \(names.formatted())"
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        store.addSpace(name: trimmedName, theme: theme.wrappedValue, icon: icon, profileID: profileID)
        close()
    }

    private func close() {
        store.draftTheme = nil
        store.isCreatingSpace = false
    }
}

/// A space's icon on a rounded glass tile, with a pencil badge to show it can be changed.
private struct IconTile: View {
    let icon: String?
    let name: String
    let accent: Color
    let size: CGFloat

    var body: some View {
        SpaceIconView(icon: icon, name: name, size: size * 0.44)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(accent.opacity(0.3)).interactive(), in: .rect(cornerRadius: size * 0.29))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.system(size: size * 0.14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: size * 0.29, height: size * 0.29)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: 5, y: 5)
            }
            .contentShape(.rect(cornerRadius: size * 0.29))
    }
}

private extension View {
    /// A row of the Create a Space form: no box, a soft highlight while its popover is open.
    func formRow(highlighted: Bool) -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(highlighted ? 0.1 : 0)))
            .contentShape(.rect)
    }
}

/// Opened from a space's right-click menu: its name, icon, theme and profile, applied as
/// they change.
struct EditSpacePopover: View {
    let spaceID: Space.ID
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @Environment(\.openSettings) private var openSettings
    @State private var name = ""
    @State private var showsIcons = false

    var body: some View {
        if let space = store.spaces.first(where: { $0.id == spaceID }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button { showsIcons = true } label: {
                        IconTile(icon: space.icon, name: space.name, accent: space.accent, size: 50)
                    }
                    .buttonStyle(.plain)
                    .help("Change icon")
                    .popover(isPresented: $showsIcons, arrowEdge: .bottom) {
                        IconPicker(icon: Binding(get: { store.spaces.first { $0.id == spaceID }?.icon },
                                                 set: { store.setIcon($0, for: spaceID) }),
                                   name: space.name, accent: space.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("Space name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: name) {
                                let trimmed = name.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { store.updateSpace(spaceID) { $0.name = trimmed } }
                            }
                    }
                }

                ThemePicker(theme: Binding(get: { store.spaces.first { $0.id == spaceID }?.resolvedTheme ?? space.resolvedTheme },
                                           set: { theme in store.updateSpace(spaceID) { $0.theme = theme } }))

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 10) {
                        ProfileBadge(profile: store.profile(for: space), size: 26)
                        Picker("Profile", selection: Binding(get: { space.profileID }, set: changeProfile)) {
                            ForEach(store.profiles) { profile in Text(profile.name).tag(profile.id) }
                        }
                        .labelsHidden()
                    }
                    Button("Edit Profiles…") { openSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    Text("Switching profiles signs this space into the other profile's accounts. Tabs and favorites stay; pages reload.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(width: 300)
            .onAppear { name = space.name }
        }
    }

    private func changeProfile(_ profileID: Profile.ID) {
        store.setProfile(profileID, for: spaceID).forEach(pool.close)
    }
}
