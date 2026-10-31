import SwiftUI
import UniformTypeIdentifiers

/// Embark ▸ Settings (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ProfilesSettings()
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
            PasswordsSettings()
                .tabItem { Label("Passwords", systemImage: "key") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            UpdatesSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 520)
    }
}

// MARK: - Layout

/// A settings page: flat rows divided by hairlines, no boxes.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 44)
                .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One setting: an optional symbol, a title with a line of detail, and its control.
private struct SettingRow<Control: View>: View {
    var symbol: String?
    let title: String
    var detail: String?
    var divided = true
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 20)
            control
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { if divided { Divider() } }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(BrowserStore.self) private var store
    @AppStorage(PreferenceKey.searchEngine) private var searchEngine = SearchEngine.google
    @AppStorage(PreferenceKey.archiveAfter) private var archiveAfter = ArchiveAfter.day
    @State private var isDefault = false
    @State private var showsImport = false

    var body: some View {
        SettingsPage {
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color(red: 0.44, green: 0.48, blue: 1), Color(red: 0.13, green: 0.7, blue: 0.65)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDefault ? "Embark is your default browser" : "Embark is not your default browser")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Links you click in other apps open in a new tab here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !isDefault {
                    Button("Make Default", action: makeDefault).buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Divider() }

            SettingRow(symbol: "magnifyingglass", title: "Search engine",
                       detail: "Used when what you type in the command bar isn’t an address.") {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingRow(symbol: "archivebox", title: "Archive tabs after",
                       detail: "Tabs you haven’t opened in that time move to the Library. Favorites, folders and splits stay.") {
                Picker("Archive tabs after", selection: $archiveAfter) {
                    ForEach(ArchiveAfter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingRow(symbol: "square.and.arrow.down", title: "Import bookmarks",
                       detail: "From Chrome, Brave, Edge, Safari or an exported HTML file, into a space you choose.",
                       divided: false) {
                Button("Import…") { showsImport = true }
            }
        }
        .sheet(isPresented: $showsImport) { ImportSheet() }
        .onAppear(perform: checkDefault)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkDefault() }
    }

    private func checkDefault() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = handler?.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    /// macOS asks the user to confirm, once for both schemes.
    private func makeDefault() {
        Task {
            for scheme in ["http", "https"] {
                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
            checkDefault()
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage(PreferenceKey.sidebarSide) private var sidebarSide = SidebarSide.left
    @AppStorage(PreferenceKey.showsAddressPill) private var showsAddressPill = true
    @AppStorage(PreferenceKey.peeksAtEdge) private var peeksAtEdge = true
    @AppStorage(PreferenceKey.newSpaceTheme) private var newSpaceTheme = NewSpaceTheme.unused

    var body: some View {
        SettingsPage {
            SettingRow(title: "Sidebar", detail: "With the sidebar on the right, the window buttons sit above the page.") {
                HStack(spacing: 14) {
                    ForEach(SidebarSide.allCases) { side in
                        Button { withAnimation(.sidebar) { sidebarSide = side } } label: {
                            VStack(spacing: 6) {
                                SidebarThumbnail(side: side)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(sidebarSide == side ? Color.accentColor : .primary.opacity(0.2),
                                                          lineWidth: sidebarSide == side ? 2.5 : 1)
                                            .padding(sidebarSide == side ? -3 : 0)
                                    }
                                Text(side == .left ? "Left" : "Right").font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SettingRow(title: "Show the address in the sidebar",
                       detail: "The pill above your favorites, with copy link, extensions and page info. Off, ⌘L still shows the address.") {
                Toggle("Show the address in the sidebar", isOn: $showsAddressPill).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Show the sidebar at the window edge",
                       detail: "While it’s hidden, moving the pointer to the edge slides it in.") {
                Toggle("Show the sidebar at the window edge", isOn: $peeksAtEdge).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "New spaces start with", detail: "You can always change it while creating the space.", divided: false) {
                Picker("New spaces start with", selection: $newSpaceTheme) {
                    ForEach(NewSpaceTheme.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
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
                    in: .rect(cornerRadius: 8))
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

// MARK: - Profiles

/// Profiles on the left; the selected one's name, color, spaces, extensions and data on the right.
struct ProfilesSettings: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var selection: Profile.ID?
    @State private var confirmsDelete = false
    @State private var clearing: Profile?

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
                .listStyle(.bordered)
                .scrollContentBackground(.hidden)
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
                .padding(.vertical, 4)
            }
            .frame(width: 210)
            .padding([.leading, .vertical], 16)

            if let profile = store.profiles.first(where: { $0.id == selection }) {
                ScrollView { detail(profile) }
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
        .sheet(item: $clearing) { ClearDataSheet(profile: $0) }
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
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ProfileBadge(profile: profile, size: 56)
                    .shadow(color: (profile.tint ?? .blue).color.opacity(0.4), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Profile name", text: Binding(get: { profile.name },
                                                            set: { name in store.updateProfile(profile.id) { $0.name = name } }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    HStack(spacing: 7) {
                        ForEach(SpaceTint.allCases, id: \.self) { tint in
                            Button { store.updateProfile(profile.id) { $0.tint = tint } } label: {
                                Circle().fill(tint.color.gradient).frame(width: 17, height: 17)
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
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) { Divider() }

            SettingRow(title: "Used by", detail: spaces.isEmpty
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

            SettingRow(title: "Browsing data", detail: "Cookies, cached files and site storage for this profile.") {
                Button("Clear…") { clearing = profile }
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
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .overlay(alignment: .bottom) { Divider() }
    }

    private func deleteSelected() {
        guard let selection, let profile = store.deleteProfile(selection) else { return }
        pool.removeData(for: profile)
        self.selection = store.profiles.first?.id
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @AppStorage(PreferenceKey.blocksThirdPartyCookies) private var blocksThirdPartyCookies = false
    @AppStorage(PreferenceKey.signsOutAtLaunch) private var signsOutAtLaunch = false
    /// nil shows every profile.
    @State private var profileFilter: Profile.ID?
    @State private var exceptions: [ProfileException] = []

    private struct ProfileException: Identifiable {
        let profile: Profile
        let exception: SiteException
        var id: String { "\(profile.id) \(exception.id)" }
    }

    var body: some View {
        SettingsPage {
            if pool.supportsSiteSettings {
                SettingRow(symbol: "eye.slash", title: "Block third-party cookies",
                           detail: "Stops most cross-site tracking. A few sign-in buttons may stop working.") {
                    Toggle("Block third-party cookies", isOn: $blocksThirdPartyCookies).labelsHidden().toggleStyle(.switch)
                }
                .onChange(of: blocksThirdPartyCookies) { pool.setBlocksThirdPartyCookies(blocksThirdPartyCookies) }
            }
            SettingRow(symbol: "rectangle.portrait.and.arrow.right", title: "Start every session signed out",
                       detail: "Clears cookies and site storage for every profile each time Embark starts.") {
                Toggle("Start every session signed out", isOn: $signsOutAtLaunch).labelsHidden().toggleStyle(.switch)
            }

            HStack {
                Text("Site permissions").font(.system(size: 13, weight: .semibold))
                Spacer()
                if pool.supportsSiteSettings {
                    Picker("Profile", selection: $profileFilter) {
                        Text("All profiles").tag(Profile.ID?.none)
                        Divider()
                        ForEach(store.profiles) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 8)

            if !pool.supportsSiteSettings {
                Text("Saved site permissions are listed in the Chromium version of Embark.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("No site has a saved permission yet. When you allow or block a site’s camera, microphone, notifications or sound, it shows up here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                permissionsTable
            }
        }
        .onAppear(perform: reload)
    }

    private var shown: [ProfileException] {
        exceptions.filter { profileFilter == nil || $0.profile.id == profileFilter }
    }

    private var permissionsTable: some View {
        VStack(spacing: 0) {
            row(site: Text("Site"), profile: Text("Profile"), permission: Text("Permission"), setting: Text("Setting"), action: nil)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(shown) { item in
                Divider()
                row(site: Text(item.exception.host).lineLimit(1),
                    profile: Text(item.profile.name).foregroundStyle(.secondary),
                    permission: Text(SitePermission(chromiumName: item.exception.contentType)?.title ?? item.exception.contentType)
                        .foregroundStyle(.secondary),
                    setting: Text(item.exception.isAllowed ? "Allowed" : "Blocked")
                        .foregroundStyle(item.exception.isAllowed ? Color.green : Color.red),
                    action: { reset(item.exception, in: item.profile) })
            }
        }
        .padding(.vertical, 4)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private func row(site: some View, profile: some View, permission: some View, setting: some View,
                     action: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            site.frame(maxWidth: .infinity, alignment: .leading)
            profile.frame(width: 90, alignment: .leading)
            permission.frame(width: 130, alignment: .leading)
            setting.frame(width: 60, alignment: .leading)
            Group {
                if let action { Button("Reset", action: action).buttonStyle(.link).font(.system(size: 12)) } else { Color.clear }
            }
            .frame(width: 44, height: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func reload() {
        exceptions = store.profiles.flatMap { profile in
            pool.siteExceptions(for: profile).map { ProfileException(profile: profile, exception: $0) }
        }
    }

    /// Chromium saves the change a few seconds later, so the row is taken out here.
    private func reset(_ exception: SiteException, in profile: Profile) {
        pool.resetSiteException(exception, for: profile)
        exceptions.removeAll { $0.profile.id == profile.id && $0.exception == exception }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettings: View {
    private static let groups: [(String, [(String, String)])] = [
        ("Tabs", [("New tab or search", "⌘T"), ("Open location", "⌘L"), ("Close tab", "⌘W"),
                  ("Add to favorites", "⌘D"), ("New folder", "⌥⌘N"), ("Back", "⌘["), ("Forward", "⌘]"), ("Reload", "⌘R")]),
        ("Spaces and sidebar", [("Next space", "⌥⌘→"), ("Previous space", "⌥⌘←"), ("Go to space 1–9", "⌃1 … ⌃9"),
                                ("Toggle sidebar", "⌘S or ⌘B"), ("Switch space", "Two-finger swipe")]),
        ("Split view", [("New split", "⌃⇧="), ("Previous pane", "⌃⇧["), ("Next pane", "⌃⇧]")]),
        ("Embark", [("Settings", "⌘,"), ("Quit", "⌘Q")]),
    ]

    var body: some View {
        SettingsPage {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 40, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(Self.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.0).font(.system(size: 13, weight: .semibold)).padding(.bottom, 6)
                        ForEach(group.1, id: \.0) { item in
                            HStack {
                                Text(item.0)
                                Spacer()
                                Text(item.1).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .frame(height: 26)
                            .overlay(alignment: .bottom) { Divider().opacity(0.6) }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Embark").font(.system(size: 24, weight: .bold))
            Text("Version \(version) · \(engine) engine").foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Link("Source on GitHub", destination: URL(string: "https://github.com/chiranjeebhub/embark-browser")!)
                Link("MIT License", destination: URL(string: "https://github.com/chiranjeebhub/embark-browser/blob/main/LICENSE")!)
                Link("Report a problem", destination: URL(string: "https://github.com/chiranjeebhub/embark-browser/issues")!)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private var engine: String {
        #if ENGINE_CEF
        "Chromium"
        #else
        "WebKit"
        #endif
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
