import SwiftUI

struct PrivacySettings: View {
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
        SettingsPage(pane: .privacy) {
            SettingsSection("Tracking and sign-ins") {
                if pool.supportsSiteSettings {
                    SettingToggle("Block third-party cookies",
                                  detail: "Stops most cross-site tracking. A few sign-in buttons may stop working.",
                                  isOn: $blocksThirdPartyCookies)
                        .onChange(of: blocksThirdPartyCookies) { pool.setBlocksThirdPartyCookies(blocksThirdPartyCookies) }
                }
                SettingToggle("Start every session signed out",
                              detail: "Clears cookies and site storage for every profile each time Embark starts.",
                              isOn: $signsOutAtLaunch)
            }

            HStack(alignment: .lastTextBaseline) {
                Text("SITE PERMISSIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
                if pool.supportsSiteSettings && !exceptions.isEmpty {
                    Picker("Profile", selection: $profileFilter) {
                        Text("All profiles").tag(Profile.ID?.none)
                        Divider()
                        ForEach(store.profiles) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 4)
            .id("Site permissions")

            if !pool.supportsSiteSettings {
                emptyNote("Saved site permissions are listed in the Chromium version of Embark.")
            } else if shown.isEmpty {
                emptyNote("No site has a saved permission yet. When you allow or block a site’s camera, microphone, notifications or sound, it shows up here.")
            } else {
                ForEach(shown) { item in
                    permissionRow(item)
                    if item.id != shown.last?.id { Divider() }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private var shown: [ProfileException] {
        exceptions.filter { profileFilter == nil || $0.profile.id == profileFilter }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
    }

    private func permissionRow(_ item: ProfileException) -> some View {
        HStack(spacing: 10) {
            FaviconView(url: URL(string: "https://\(item.exception.host)") ?? URL(string: "https://example.com")!, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.exception.host).lineLimit(1)
                Text(item.profile.name).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(SitePermission(chromiumName: item.exception.contentType)?.title ?? item.exception.contentType)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(item.exception.isAllowed ? "Allowed" : "Blocked")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.exception.isAllowed ? Color.green : Color.red)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background((item.exception.isAllowed ? Color.green : Color.red).opacity(0.12), in: .capsule)
                .frame(width: 76, alignment: .leading)
            Button("Reset") { reset(item.exception, in: item.profile) }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .padding(.vertical, 8)
    }

    private func reload() {
        exceptions = store.profiles.flatMap { profile in
            pool.siteExceptions(for: profile).map { ProfileException(profile: profile, exception: $0) }
        }
    }

    /// Chromium saves the change a few seconds later, so the row is taken out here.
    private func reset(_ exception: SiteException, in profile: Profile) {
        pool.resetSiteException(exception, for: profile)
        withAnimation(.snappy) {
            exceptions.removeAll { $0.profile.id == profile.id && $0.exception == exception }
        }
    }
}
