import SwiftUI

/// After a sign-in: offers to keep the password in the Keychain, or to update it.
struct SavePasswordCard: View {
    let tabID: BrowserTab.ID
    let login: PendingLogin
    @Environment(PagePool.self) private var pool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill").font(.system(size: 18)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(login.isUpdate ? "Update saved password for \(login.host)?" : "Save password for \(login.host)?")
                    .font(.system(size: 13, weight: .semibold))
                Text(login.username.isEmpty ? "No user name" : login.username)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !login.isUpdate {
                Button("Never") { pool.answerSaveLogin(for: tabID, save: false, never: true) }
                    .help("Never offer to save passwords for \(login.host)")
            }
            Button("Not Now") { pool.answerSaveLogin(for: tabID, save: false) }
                .keyboardShortcut(.cancelAction)
            Button(login.isUpdate ? "Update" : "Save") { pool.answerSaveLogin(for: tabID, save: true) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

/// On a page with a sign-in form and saved logins: fills one in with a click. Nothing is
/// filled until it's clicked.
struct FillPasswordCard: View {
    let tabID: BrowserTab.ID
    let logins: [SavedLogin]
    @Environment(PagePool.self) private var pool
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(.tint)
                if logins.count == 1, let login = logins.first {
                    Button { fill(login) } label: {
                        Text("Sign in as **\(login.username.isEmpty ? login.host : login.username)**")
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu("Use a saved password") {
                        ForEach(logins) { login in
                            Button(login.username.isEmpty ? login.host : login.username) { fill(login) }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                Button { isDismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func fill(_ login: SavedLogin) {
        pool.fill(login, in: tabID)
        isDismissed = true
    }
}
