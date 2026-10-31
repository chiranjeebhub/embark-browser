import AppKit
import SwiftUI

struct GeneralSettings: View {
    @AppStorage(PreferenceKey.searchEngine) private var searchEngine = SearchEngine.google
    @AppStorage(PreferenceKey.archiveAfter) private var archiveAfter = ArchiveAfter.day
    @AppStorage(PreferenceKey.opensLinksInLittleWindow) private var opensLinksInLittleWindow = true
    @State private var isDefault = false
    @State private var showsImport = false

    var body: some View {
        SettingsPage(pane: .general) {
            SettingsSection("Browser") {
                SettingRow("Default browser",
                           detail: isDefault ? "Links you click in other apps open here." : "Embark isn’t your default browser yet. Links you click in other apps open in another browser.") {
                    Image(systemName: "globe")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(LinearGradient(colors: SettingsPane.about.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: .rect(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color(red: 0.3, green: 0.4, blue: 0.95).opacity(0.35), radius: 7, y: 3)
                } control: {
                    if isDefault {
                        Label("Default", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button("Make Default", action: makeDefault)
                            .buttonStyle(.glassProminent)
                    }
                }
                SettingRow("Search engine", detail: "Used when what you type in the command bar isn’t an address.") {
                    Picker("Search engine", selection: $searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection("Tabs") {
                SettingRow("Archive tabs after",
                           detail: "Unused tabs move to the Library. Favorites, folders and splits stay.") {
                    Picker("Archive tabs after", selection: $archiveAfter) {
                        ForEach(ArchiveAfter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            SettingsSection("Links from other apps") {
                SettingToggle("Open links in Little windows",
                              detail: "A small window you can glance at and close, or move into a space with ⌘O. Sites a space has as a favorite still open in that space.",
                              isOn: $opensLinksInLittleWindow) {
                    LittleWindowThumbnail()
                }
            }

            SettingsSection("Import") {
                SettingRow("Import bookmarks",
                           detail: "From Chrome, Brave, Edge, Safari or an exported HTML file, into a space you choose.") {
                    Button("Import…") { showsImport = true }
                }
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

/// A tiny Little window floating over a space.
private struct LittleWindowThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.73, green: 0.7, blue: 0.98), Color(red: 0.66, green: 0.87, blue: 0.89)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 64, height: 44)
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.background)
                    .frame(width: 34, height: 26)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 2) {
                            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                        }
                        .frame(width: 13, height: 3)
                        .padding(4)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(5)
            }
            .accessibilityHidden(true)
    }
}
