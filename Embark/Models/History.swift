import Foundation

/// A page you visited. Visits to the same address in the same profile share one entry.
struct HistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var url: URL
    var title: String
    var profileID: Profile.ID
    var lastVisited: Date
    var visitCount = 1
}

/// Pages visited, newest first, kept per profile.
struct History: Codable {
    private(set) var entries: [HistoryEntry] = []

    /// Oldest entries are dropped past this.
    static let limit = 20_000

    /// Only web pages are kept; internal and extension pages aren't.
    static func isRecorded(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    mutating func recordVisit(to url: URL, title: String?, profileID: Profile.ID, at date: Date = .now) {
        guard Self.isRecorded(url) else { return }
        let title = title?.isEmpty == false ? title! : (url.host() ?? url.absoluteString)
        if let i = entries.firstIndex(where: { $0.url == url && $0.profileID == profileID }) {
            var entry = entries.remove(at: i)
            entry.title = title
            entry.lastVisited = date
            entry.visitCount += 1
            entries.insert(entry, at: 0)
        } else {
            entries.insert(HistoryEntry(url: url, title: title, profileID: profileID, lastVisited: date), at: 0)
            if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        }
    }

    /// A page's title arrives after its address; this fills it in without counting a visit.
    /// Returns false when the entry already had that title.
    @discardableResult
    mutating func updateTitle(_ title: String, for url: URL, profileID: Profile.ID) -> Bool {
        guard !title.isEmpty, let i = entries.firstIndex(where: { $0.url == url && $0.profileID == profileID }),
              entries[i].title != title else { return false }
        entries[i].title = title
        return true
    }

    mutating func remove(_ ids: Set<HistoryEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    /// Deletes visits since `date` (everything when nil), in one profile or all of them.
    mutating func clear(since date: Date? = nil, profileID: Profile.ID? = nil) {
        entries.removeAll { entry in
            (date.map { entry.lastVisited >= $0 } ?? true) && (profileID.map { entry.profileID == $0 } ?? true)
        }
    }

    mutating func removeProfile(_ profileID: Profile.ID) {
        entries.removeAll { $0.profileID == profileID }
    }

    /// Entries whose title or address contain every word of `query`, best first: title and
    /// host matches, then how often and how recently the page was visited.
    func search(_ query: String, profileID: Profile.ID? = nil, limit: Int = 50, now: Date = .now) -> [HistoryEntry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = entries.filter { entry in
            guard profileID.map({ entry.profileID == $0 }) ?? true else { return false }
            let haystack = (entry.title + " " + entry.url.absoluteString).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        guard !words.isEmpty else { return Array(matches.prefix(limit)) }
        func score(_ entry: HistoryEntry) -> Double {
            let host = (entry.url.host() ?? "").lowercased()
            let title = entry.title.lowercased()
            var score = 0.0
            for word in words {
                if host.hasPrefix(word) || host.contains(".\(word)") { score += 4 }
                if title.hasPrefix(word) || title.contains(" \(word)") { score += 2 }
            }
            score += log2(Double(entry.visitCount) + 1)
            let days = now.timeIntervalSince(entry.lastVisited) / 86_400
            score += max(0, 3 - days / 7)
            return score
        }
        return Array(matches.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }

    /// Entries grouped by the day they were last visited, newest day first.
    static func byDay(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [(day: Date, entries: [HistoryEntry])] {
        var groups: [(day: Date, entries: [HistoryEntry])] = []
        for entry in entries.sorted(by: { $0.lastVisited > $1.lastVisited }) {
            let day = calendar.startOfDay(for: entry.lastVisited)
            if groups.last?.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }
}
