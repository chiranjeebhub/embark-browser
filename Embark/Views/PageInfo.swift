import SwiftUI

/// Page info, from the sliders button at the end of the address bar: the connection, the
/// site's permissions, its cookies, and a way into its settings. Settings are per site and
/// kept by the space's profile.
struct PageInfoPopover: View {
    let tab: BrowserTab
    @Binding var isPresented: Bool
    @Binding var showsSiteSettings: Bool
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var screen = Screen.main
    @State private var values: [SitePermission: PermissionValue] = [:]
    /// The profile's value for sites without their own setting, per permission.
    @State private var defaults: [SitePermission: PermissionValue] = [:]
    @State private var cookieCount: Int?
    @State private var isDeleting = false

    private enum Screen { case main, connection, cookies }

    private var page: BrowserPage? { pool.existingPage(for: tab.id) }
    private var host: String { tab.url.host() ?? tab.url.absoluteString }
    private var security: PageSecurity { page?.security ?? PageSecurity(isSecure: false, hasCertificateError: false, certificate: nil) }
    private var isSecure: Bool { tab.url.scheme == "https" && !security.hasCertificateError }

    /// Like Chrome: permissions the site used or that were changed, plus Sound.
    private var shownPermissions: [SitePermission] {
        let used = pool.usedPermissions[host] ?? []
        return SitePermission.allCases.filter { $0 == .sound || used.contains($0) || isChanged($0) }
    }

    private func isChanged(_ permission: SitePermission) -> Bool {
        (values[permission] ?? .default) != (defaults[permission] ?? .default)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch screen {
            case .main: main
            case .connection: connection
            case .cookies: cookies
            }
        }
        .frame(width: 320)
        .padding(.vertical, 10)
        .onAppear(perform: load)
        .animation(.snappy(duration: 0.2), value: screen)
    }

    // MARK: Screens

    private var main: some View {
        VStack(alignment: .leading, spacing: 2) {
            header(host, back: nil)
            Divider().padding(.vertical, 6)
            NavigationRow(symbol: isSecure ? "lock" : "exclamationmark.triangle",
                          tint: isSecure ? nil : .orange,
                          title: isSecure ? "Connection is secure" : "Not secure",
                          subtitle: nil) { screen = .connection }
            Divider().padding(.vertical, 6)
            ForEach(shownPermissions) { permission in
                PermissionRow(permission: permission, value: values[permission] ?? .default,
                              isDefault: !isChanged(permission)) { set(permission, $0) }
            }
            if SitePermission.allCases.contains(where: isChanged) {
                Button("Reset permissions", action: resetPermissions)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            Divider().padding(.vertical, 6)
            NavigationRow(symbol: "server.rack", title: "Cookies and site data",
                          subtitle: cookieCount.map { $0 == 1 ? "1 cookie" : "\($0) cookies" }) { screen = .cookies }
            NavigationRow(symbol: "gearshape", title: "Site settings", subtitle: nil) {
                isPresented = false
                showsSiteSettings = true
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(isSecure ? "Connection is secure" : "Not secure", back: .main)
            Divider()
            Text(isSecure
                 ? "Information you send to this site, like passwords or card numbers, is private while it travels."
                 : security.hasCertificateError
                     ? "This site's certificate isn't valid. Someone could be pretending to be \(host)."
                     : "This site doesn't use a secure connection. Don't enter passwords or card numbers.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .fixedSize(horizontal: false, vertical: true)
            if let certificate = security.certificate {
                VStack(alignment: .leading, spacing: 6) {
                    detail("Issued to", certificate.subject)
                    detail("Issued by", certificate.issuer)
                    detail("Valid from", certificate.validFrom.formatted(date: .abbreviated, time: .omitted))
                    detail("Valid until", certificate.validUntil.formatted(date: .abbreviated, time: .omitted))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.05)))
                .padding(.horizontal, 10)
            }
        }
    }

    private var cookies: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Cookies and site data", back: .main)
            Divider()
            HStack {
                Image(systemName: "server.rack").frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host).font(.system(size: 13, weight: .medium))
                    Text(cookieCount.map { $0 == 1 ? "1 cookie in use" : "\($0) cookies in use" } ?? "Counting…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isDeleting ? "Deleting…" : "Delete", role: .destructive, action: deleteSiteData)
                    .controlSize(.small)
                    .disabled(isDeleting)
            }
            .padding(.horizontal, 14)
            Text("Deleting signs you out of this site and removes what it stored on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            Button("Manage on-device site data") {
                isPresented = false
                if let url = URL(string: "chrome://settings/content/siteDetails?site=\(tab.url.scheme ?? "https")://\(host)") {
                    store.openTab(url, title: "Site data")
                }
            }
            .buttonStyle(.link)
            .padding(.horizontal, 14)
        }
    }

    // MARK: Pieces

    private func header(_ title: String, back: Screen?) -> some View {
        HStack(spacing: 8) {
            if let back {
                Button { screen = back } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
            }
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer()
            Button { isPresented = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    // MARK: Actions

    private func load() {
        cookieCount = nil
        guard let page else { return }
        for permission in SitePermission.allCases {
            values[permission] = page.permission(permission)
            defaults[permission] = page.defaultPermission(permission)
        }
        page.countCookies { cookieCount = $0 }
    }

    private func set(_ permission: SitePermission, _ value: PermissionValue) {
        page?.setPermission(permission, to: value)
        // Back to default reads as the profile's value again.
        values[permission] = value == .default ? (page?.permission(permission) ?? .default) : value
        if permission == .sound { pool.setSiteMuted(value == .block, host: host) }
    }

    private func resetPermissions() {
        for permission in SitePermission.allCases where isChanged(permission) {
            set(permission, .default)
        }
    }

    private func deleteSiteData() {
        guard let page else { return }
        isDeleting = true
        page.clearSiteData {
            isDeleting = false
            page.reload()
            page.countCookies { cookieCount = $0 }
        }
    }
}

/// A permission with a switch: on allows, off blocks. Sound off mutes the site.
private struct PermissionRow: View {
    let permission: SitePermission
    let value: PermissionValue
    /// The site uses the profile's value rather than its own.
    let isDefault: Bool
    let set: (PermissionValue) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? permission.symbol : permission.symbol + ".slash")
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title).font(.system(size: 13))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(permission.title, isOn: Binding(get: { isOn }, set: { on in set(on ? .allow : .block) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var isOn: Bool {
        switch permission {
        case .sound, .autoPictureInPicture: value != .block
        default: value == .allow
        }
    }

    private var subtitle: String {
        if isDefault, permission == .sound || permission == .autoPictureInPicture, value != .block {
            return "Automatic (default)"
        }
        let word = switch value {
        case .allow: "Allowed"
        case .block: permission == .sound ? "Muted" : "Blocked"
        default: "Ask"
        }
        return isDefault ? "\(word) (default)" : word
    }
}

/// A row that opens a subpage.
private struct NavigationRow: View {
    let symbol: String
    var tint: Color?
    let title: String
    let subtitle: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 22).foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(hovering ? 0.06 : 0)).padding(.horizontal, 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Every permission for one site, with Default / Allow / Block.
struct SiteSettingsSheet: View {
    let tab: BrowserTab
    @Environment(PagePool.self) private var pool
    @Environment(\.dismiss) private var dismiss
    @State private var values: [SitePermission: PermissionValue] = [:]

    private var page: BrowserPage? { pool.existingPage(for: tab.id) }

    var body: some View {
        Form {
            Section(tab.url.host() ?? tab.url.absoluteString) {
                ForEach(SitePermission.allCases) { permission in
                    Picker(selection: Binding(get: { values[permission] ?? .default }, set: { value in
                        page?.setPermission(permission, to: value)
                        values[permission] = value
                        if permission == .sound, let host = tab.url.host() { pool.setSiteMuted(value == .block, host: host) }
                    })) {
                        Text("Default").tag(PermissionValue.default)
                        Text(permission == .sound ? "On" : "Allow").tag(PermissionValue.allow)
                        Text(permission == .sound ? "Muted" : "Block").tag(PermissionValue.block)
                    } label: {
                        Label(permission.title, systemImage: permission.symbol)
                    }
                }
            }
            Text("Settings apply to this site in the current space's profile.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear {
            guard let page else { return }
            for permission in SitePermission.allCases { values[permission] = page.permission(permission) }
        }
    }
}

/// "site.com wants to use your camera", over the page that asked.
struct PermissionPromptCard: View {
    let request: TabPermissionRequest
    @Environment(PagePool.self) private var pool

    var body: some View {
        let permissions = request.request.permissions
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permissions.first?.symbol ?? "questionmark")
                .font(.system(size: 18))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(request.request.host) wants to \(ListFormatter.localizedString(byJoining: permissions.map(\.ask)))")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Block") { pool.answer(request, allow: false) }
                        .keyboardShortcut(.cancelAction)
                    Button("Allow") { pool.answer(request, allow: true) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
