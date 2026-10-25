import AppKit
import Observation

/// Browsing history, saved to Application Support as JSON a moment after each change.
@MainActor
@Observable
final class HistoryStore {
    private(set) var history = History()
    @ObservationIgnored private var saveGeneration = 0
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = BrowserStore.supportDirectory.appending(path: "history.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(History.self, from: data) {
            history = saved
        }
        nonisolated(unsafe) let store = self
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { store.writeNow() }
        }
    }

    var entries: [HistoryEntry] { history.entries }

    func recordVisit(to url: URL, title: String?, profileID: Profile.ID) {
        history.recordVisit(to: url, title: title, profileID: profileID)
        save()
    }

    func updateTitle(_ title: String, for url: URL, profileID: Profile.ID) {
        history.updateTitle(title, for: url, profileID: profileID)
        save()
    }

    func search(_ query: String, profileID: Profile.ID? = nil, limit: Int = 50) -> [HistoryEntry] {
        history.search(query, profileID: profileID, limit: limit)
    }

    func remove(_ ids: Set<HistoryEntry.ID>) {
        history.remove(ids)
        save()
    }

    func clear(since date: Date? = nil, profileID: Profile.ID? = nil) {
        history.clear(since: date, profileID: profileID)
        save()
    }

    func removeProfile(_ profileID: Profile.ID) {
        history.removeProfile(profileID)
        save()
    }

    /// Waits a few seconds so a page that changes its title repeatedly writes once.
    private func save() {
        saveGeneration += 1
        let generation = saveGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard saveGeneration == generation else { return }
            writeNow()
        }
    }

    private func writeNow() {
        let history = history
        let fileURL = fileURL
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
