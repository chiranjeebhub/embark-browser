import SwiftUI

/// Settings ▸ Updates: the installed version, the last check, and whether Embark checks for and
/// installs updates by itself.
struct UpdatesSettings: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        SettingsPage(pane: .updates) {
            SettingsSection("This Mac") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Embark \(version)")
                        statusLine
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 20)
                    if case .ready = updater.status {
                        Button("Restart to Update") { updater.installNow() }
                            .buttonStyle(.glassProminent)
                    } else if updater.isAvailable {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(updater.isChecking)
                    }
                }
                .padding(.vertical, 13)
            }

            if updater.isAvailable {
                SettingsSection("Automatic updates") {
                    SettingToggle("Check for updates automatically",
                                  detail: "Embark looks for a new version once a day.",
                                  isOn: $updater.checksAutomatically)
                    SettingToggle("Download and install updates automatically",
                                  detail: "Updates download in the background and install the next time you quit Embark.",
                                  isOn: $updater.installsAutomatically)
                        .disabled(!updater.checksAutomatically)
                }
            } else {
                Text("This copy of Embark was built without an update key, so it can’t check for updates. Copies downloaded from GitHub Releases update themselves.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                Link("Download Embark from GitHub",
                     destination: URL(string: "https://github.com/chiranjeebhub/embark-browser/releases/latest")!)
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

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
