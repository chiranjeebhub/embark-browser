import AppKit
import Observation

/// Everything the windows share: profiles, spaces, favorites and tabs. Saved to Application
/// Support as JSON.
@Observable
final class BrowserLibrary {
    static let shared = BrowserLibrary()

    var profiles: [Profile] = [] { didSet { save() } }
    var spaces: [Space] = [] { didSet { save() } }
    /// The space shown last, which a new window or the next launch starts on.
    var lastSelectedSpaceID: Space.ID? { didSet { save() } }

    @ObservationIgnored private var isLoading = false
    /// Bumped by each change; a write waits briefly so a drag in the theme picker saves once.
    @ObservationIgnored private var saveGeneration = 0
    @ObservationIgnored private let fileURL = BrowserStore.supportDirectory.appending(path: "state.json")
    /// False for a private window's library, which is never written to disk.
    @ObservationIgnored private let persists: Bool

    init() {
        persists = true
        load()
        if spaces.isEmpty { seed() }
        nonisolated(unsafe) let library = self
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            library.writeNow()
        }
    }

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var spaces: [Space]
        var selectedSpaceID: Space.ID?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isLoading = true
        profiles = snapshot.profiles
        // Profiles saved before badge colors get distinct ones.
        for i in profiles.indices where profiles[i].tint == nil {
            let used = Set(profiles.compactMap(\.tint))
            profiles[i].tint = SpaceTint.allCases.first { !used.contains($0) } ?? .blue
        }
        spaces = snapshot.spaces
        lastSelectedSpaceID = snapshot.selectedSpaceID ?? snapshot.spaces.first?.id
        isLoading = false
    }

    /// A private window's own library: one space on a new private profile, in memory only.
    init(privateWindow: Void) {
        persists = false
        let profile = Profile(name: "Private", tint: .graphite, isPrivate: true)
        let theme = SpaceTheme(colors: [SpaceTint.graphite.themeColor], intensity: 0.12, appearance: .dark)
        let space = Space(name: "Private", theme: theme, icon: "eyeglasses", profileID: profile.id)
        profiles = [profile]
        spaces = [space]
        lastSelectedSpaceID = space.id
    }

    private func save() {
        guard persists, !isLoading else { return }
        saveGeneration += 1
        let generation = saveGeneration
        nonisolated(unsafe) let library = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard library.saveGeneration == generation else { return }
            library.writeNow()
        }
    }

    private func writeNow() {
        let snapshot = Snapshot(profiles: profiles, spaces: spaces, selectedSpaceID: lastSelectedSpaceID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seed() {
        isLoading = true
        let personal = Profile(name: "Personal", tint: .purple)
        let work = Profile(name: "Work", tint: .blue)
        profiles = [personal, work]
        func fav(_ title: String, _ url: String) -> Favorite { Favorite(title: title, url: URL(string: url)!) }
        spaces = [
            Space(name: "Personal", theme: SpaceTheme(tint: .purple), icon: "house.fill", profileID: personal.id, favorites: [
                fav("Gmail", "https://mail.google.com"),
                fav("YouTube", "https://www.youtube.com"),
                fav("WhatsApp", "https://web.whatsapp.com"),
                fav("Maps", "https://maps.google.com"),
            ]),
            Space(name: "Work", theme: SpaceTheme(tint: .blue), icon: "briefcase.fill", profileID: work.id, favorites: [
                fav("Gmail", "https://mail.google.com"),
                fav("Calendar", "https://calendar.google.com"),
                fav("Slack", "https://app.slack.com"),
                fav("GitHub", "https://github.com"),
            ]),
        ]
        lastSelectedSpaceID = spaces.first?.id
        isLoading = false
        save()
    }
}
