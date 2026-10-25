import AppKit
import Observation

/// Browsing history, saved to Application Support as JSON a moment after each change.
/// Reading and writing the file happen off the main thread: it holds up to 20,000 pages.
@MainActor
@Observable
final class HistoryStore {
    private(set) var history = History()
    @ObservationIgnored private var saveGeneration = 0
    @ObservationIgnored private let fileURL: URL
    /// Until the saved file is read, nothing is written over it.
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var savesWhenLoaded = false
    private static let disk = DispatchQueue(label: "dev.embark.history", qos: .utility)

    init(fileURL: URL = BrowserStore.supportDirectory.appending(path: "history.json")) {
        self.fileURL = fileURL
        Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(History.self, from: $0) }
            }.value
            self?.finishLoading(saved)
        }
        nonisolated(unsafe) let store = self
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { store.writeNow(waiting: true) }
        }
    }

    /// Visits made while the file was being read go on top of the saved history.
    private func finishLoading(_ saved: History?) {
        if var merged = saved {
            for entry in history.entries.reversed() {
                merged.recordVisit(to: entry.url, title: entry.title, profileID: entry.profileID, at: entry.lastVisited)
            }
            history = merged
        }
        isLoaded = true
        if savesWhenLoaded { save() }
    }

    var entries: [HistoryEntry] { history.entries }

    func recordVisit(to url: URL, title: String?, profileID: Profile.ID) {
        history.recordVisit(to: url, title: title, profileID: profileID)
        save()
    }

    func updateTitle(_ title: String, for url: URL, profileID: Profile.ID) {
        if history.updateTitle(title, for: url, profileID: profileID) { save() }
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
        guard isLoaded else { savesWhenLoaded = true; return }
        saveGeneration += 1
        let generation = saveGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard saveGeneration == generation else { return }
            writeNow()
        }
    }

    private func writeNow(waiting: Bool = false) {
        guard isLoaded else { return }
        nonisolated(unsafe) let history = history
        let fileURL = fileURL
        let write: @Sendable () -> Void = {
            guard let data = try? JSONEncoder().encode(history) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
        if waiting { Self.disk.sync(execute: write) } else { Self.disk.async(execute: write) }
    }
}
