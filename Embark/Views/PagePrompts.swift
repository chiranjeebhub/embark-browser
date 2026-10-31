import SwiftUI

/// A site's sign-in prompt (HTTP authentication), over the top of its page.
struct CredentialPromptCard: View {
    let tabID: BrowserTab.ID
    let request: CredentialRequest
    @Environment(PagePool.self) private var pool
    @State private var user = ""
    @State private var password = ""
    @FocusState private var focusesUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: request.isProxy ? "network" : "person.badge.key").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.isProxy ? "The proxy \(request.host) needs you to sign in" : "Sign in to \(request.host)")
                        .font(.system(size: 13, weight: .semibold))
                    if let realm = request.realm {
                        Text(realm).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            TextField("User name", text: $user)
                .textContentType(.username)
                .focused($focusesUser)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
            HStack {
                Text("Your connection to this site isn't private if it doesn't use https.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .opacity(isSecure ? 0 : 1)
                Spacer()
                Button("Cancel") { pool.answerCredentials(for: tabID, user: nil, password: nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Sign In", action: signIn)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(user.isEmpty)
            }
            .controlSize(.small)
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(width: 360)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .onAppear { focusesUser = true }
    }

    private var isSecure: Bool {
        pool.store?.library.spaces.lazy.compactMap { $0.pageTab(tabID) }.first?.url.scheme == "https"
    }

    private func signIn() {
        guard !user.isEmpty else { return }
        pool.answerCredentials(for: tabID, user: user, password: password)
    }
}

/// Covers a page whose certificate isn't trusted, as Chrome does, until you go back or
/// choose to visit it anyway.
struct CertificateWarningView: View {
    let tabID: BrowserTab.ID
    let warning: CertificateWarning
    @Environment(PagePool.self) private var pool
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Your connection isn't private")
                .font(.system(size: 22, weight: .semibold))
            Text("Someone may be trying to read what you send to **\(warning.url.host() ?? warning.url.absoluteString)**, like passwords or card numbers. \(warning.description)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(showsDetails ? "Hide Details" : "Details") { withAnimation(.snappy) { showsDetails.toggle() } }
                    .buttonStyle(.link)
                Spacer()
                Button("Go Back") { pool.answerCertificateWarning(for: tabID, proceed: false) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            if showsDetails {
                Divider()
                Text("Only continue if you know why this site's certificate isn't trusted, for example a device on your own network.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Visit \(warning.url.host() ?? "This Site") Anyway", role: .destructive) {
                    pool.answerCertificateWarning(for: tabID, proceed: true)
                }
                .buttonStyle(.link)
                .foregroundStyle(.red)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: 460)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Covers a page whose renderer crashed, as Chrome's "Aw, Snap!" does, until it's reloaded.
struct CrashedPageView: View {
    let tabID: BrowserTab.ID
    let outOfMemory: Bool
    @Environment(PagePool.self) private var pool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: outOfMemory ? "memorychip" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(outOfMemory ? "This page ran out of memory" : "This page crashed")
                .font(.system(size: 20, weight: .semibold))
            Text("Reload it to pick up where you left off.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Reload") { pool.reloadCrashedTab(tabID) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// On a page whose video needs H.264, which Chromium here can't play: offers to open the site
/// in macOS's WebKit instead. Nothing moves until it's clicked, since that reloads the page.
struct UnsupportedVideoCard: View {
    let tabID: BrowserTab.ID
    @Environment(PagePool.self) private var pool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.slash").font(.system(size: 18)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("This video can't play in Chromium")
                    .font(.system(size: 13, weight: .semibold))
                Text("The Safari engine can play it. The page reloads, and you may need to sign in to this site again.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Not Now") { pool.dismissUnsupportedVideo(tabID) }
            Button("Play in Safari Engine") { pool.playInSystemEngine(tabID) }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
