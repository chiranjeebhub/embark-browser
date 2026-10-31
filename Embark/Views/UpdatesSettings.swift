import SwiftUI

/// Settings ▸ Updates: the installed version, the last check, and whether Embark checks for and
/// installs updates by itself.
struct UpdatesSettings: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.vertical, 22)
                    .overlay(alignment: .bottom) { Divider() }
                if updater.isAvailable {
                    row(title: "Check for updates automatically",
                        detail: "Embark looks for a new version once a day.") {
                        Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    row(title: "Download and install updates automatically",
                        detail: "Updates download in the background and install the next time you quit Embark.",
                        divided: false) {
                        Toggle("Download and install updates automatically", isOn: $updater.installsAutomatically)
                            .labelsHidden().toggleStyle(.switch)
                            .disabled(!updater.checksAutomatically)
                    }
                } else {
                    Text("This copy of Embark was built without an update key, so it can’t check for updates. Copies downloaded from GitHub Releases update themselves.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 13)
                    Link("Download Embark from GitHub",
                         destination: URL(string: "https://github.com/chiranjeebhub/embark-browser/releases/latest")!)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Embark \(version)").font(.system(size: 17, weight: .semibold))
                statusLine
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            if case .ready = updater.status {
                Button("Restart to Update") { updater.installNow() }
                    .buttonStyle(.borderedProminent)
            } else if updater.isAvailable {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(updater.isChecking)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if updater.isChecking {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
            }
        } else {
            switch updater.status {
            case .ready(let version):
                Text("Embark \(version) is ready. It installs when you quit, or restart now.")
            case .found(let version):
                Text("Embark \(version) is available.")
            case .failed(let message):
                Text("Couldn’t check for updates: \(message)")
            case .upToDate, .idle:
                if !updater.isAvailable {
                    Text("Updates are off in this build.")
                } else if let lastCheck = updater.lastCheck {
                    Text("\(updater.status == .upToDate ? "Embark is up to date. " : "")Last checked \(lastCheck.formatted(.relative(presentation: .named))).")
                } else {
                    Text("Not checked yet.")
                }
            }
        }
    }

    private func row<Control: View>(title: String, detail: String, divided: Bool = true,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            control()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { if divided { Divider() } }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
