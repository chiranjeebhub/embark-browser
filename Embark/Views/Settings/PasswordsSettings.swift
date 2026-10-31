import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Passwords: the logins saved in the Keychain for each profile. Showing, copying or
/// exporting a password asks for Touch ID or the Mac's password first.
struct PasswordsSettings: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var profileID: Profile.ID?
    @State private var search = ""
    @State private var revealed: [SavedLogin.ID: String] = [:]
    @State private var notice: String?

    private var passwords: PasswordStore { pool.passwords }

    private var selectedProfileID: Profile.ID? { profileID ?? store.profiles.first?.id }

    private var shown: [SavedLogin] {
        guard let selectedProfileID else { return [] }
        let all = passwords.all(for: selectedProfileID)
        let words = search.lowercased().split(separator: " ")
        return all.filter { login in words.allSatisfy { login.host.contains($0) || login.username.lowercased().contains($0) } }
    }

    var body: some View {
        SettingsPage(pane: .passwords) {
            HStack(spacing: 10) {
                Picker("Profile", selection: Binding(get: { selectedProfileID }, set: { profileID = $0; revealed = [:] })) {
                    ForEach(store.profiles) { profile in
                        Text(profile.name.isEmpty ? "Untitled" : profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(width: 210, height: 26)
                .background(.primary.opacity(0.06), in: .capsule)
            }
            .padding(.top, 22)
            .padding(.bottom, 6)
            .id("Saved passwords")

            if shown.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No Saved Passwords" : "No Matches", systemImage: "key",
                                       description: Text(search.isEmpty ? "Embark offers to save a password after you sign in to a site." : ""))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { login in
                        row(login)
                        if login.id != shown.last?.id { Divider() }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Import…", action: importCSV)
                    .help("Import a CSV file exported from the Passwords app, Safari, Chrome or a password manager")
                Button("Export…") { Task { await exportCSV() } }
                    .disabled(shown.isEmpty && search.isEmpty)
                if let notice {
                    Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Kept in your Mac’s Keychain", systemImage: "lock.fill")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            if !passwords.neverSaveHosts.isEmpty {
                SettingsSection("Never saved") {
                    ForEach(passwords.neverSaveHosts.sorted(), id: \.self) { host in
                        HStack {
                            FaviconView(url: URL(string: "https://\(host)") ?? URL(string: "https://example.com")!, size: 16)
                            Text(host)
                            Spacer()
                            Button("Remove") { passwords.allowSaving(host) }.controlSize(.small)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onAppear { passwords.reload() }
    }

    private func row(_ login: SavedLogin) -> some View {
        HStack(spacing: 10) {
            FaviconView(url: URL(string: "https://\(login.host)") ?? URL(string: "https://example.com")!, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(login.host).font(.system(size: 13, weight: .medium))
                Text(login.username.isEmpty ? "No user name" : login.username)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(revealed[login.id] ?? "••••••••")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Button {
                if revealed[login.id] != nil { revealed[login.id] = nil } else { Task { await reveal(login) } }
            } label: { Image(systemName: revealed[login.id] == nil ? "eye" : "eye.slash") }
                .help(revealed[login.id] == nil ? "Show Password" : "Hide Password")
            Button { Task { await copy(login) } } label: { Image(systemName: "doc.on.doc") }
                .help("Copy Password")
            Button(role: .destructive) { passwords.delete(login); revealed[login.id] = nil } label: { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 9)
    }

    private func reveal(_ login: SavedLogin) async {
        guard await PasswordStore.authenticate(reason: "show the password for \(login.host)") else { return }
        revealed[login.id] = passwords.password(for: login)
    }

    private func copy(_ login: SavedLogin) async {
        guard await PasswordStore.authenticate(reason: "copy the password for \(login.host)"),
              let password = passwords.password(for: login) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
        notice = "Copied the password for \(login.host)."
    }

    private func importCSV() {
        guard let selectedProfileID else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Choose a passwords CSV. In the Passwords app, use File ▸ Export All Passwords."
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let count = passwords.importCSV(text, into: selectedProfileID)
        notice = count == 1 ? "Imported 1 password." : "Imported \(count) passwords."
    }

    private func exportCSV() async {
        guard let selectedProfileID,
              await PasswordStore.authenticate(reason: "export your saved passwords") else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Embark Passwords.csv"
        panel.message = "Anyone who opens this file can read your passwords. Delete it after importing it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try passwords.exportCSV(for: selectedProfileID).write(to: url, atomically: true, encoding: .utf8)
            notice = "Exported. In the Passwords app, use File ▸ Import Passwords."
        } catch {
            notice = "Couldn't save the file."
        }
    }
}
