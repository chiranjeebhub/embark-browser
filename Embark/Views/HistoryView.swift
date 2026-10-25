import SwiftUI

/// ⌘Y: every page visited in a profile, by day, with search. Opening one brings it up as a tab
/// in a space that uses the same profile, so it's signed in the same way.
struct HistoryView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(PagePool.self) private var pool
    @State private var query = ""
    @State private var profileID: Profile.ID?
    @State private var selection: Set<HistoryEntry.ID> = []
    @State private var confirmsClear = false

    var body: some View {
        let entries = pool.history.search(query, profileID: currentProfileID, limit: query.isEmpty ? 2_000 : 500)
        Group {
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No History" : "No Results",
                                       systemImage: query.isEmpty ? "clock" : "magnifyingglass",
                                       description: Text(query.isEmpty ? "Pages you visit show up here." : "Nothing matches \u{201C}\(query)\u{201D}."))
            } else {
                List(selection: $selection) {
                    if query.isEmpty {
                        ForEach(History.byDay(entries), id: \.day) { group in
                            Section(Self.dayTitle(group.day)) {
                                ForEach(group.entries) { row($0) }
                            }
                        }
                    } else {
                        ForEach(entries) { row($0) }
                    }
                }
                .onDeleteCommand { pool.history.remove(selection); selection = [] }
                .contextMenu(forSelectionType: HistoryEntry.ID.self) { ids in
                    Button("Open") { open(ids) }
                    Button("Copy Link") { copy(ids) }
                    Divider()
                    Button("Delete", role: .destructive) { pool.history.remove(ids); selection.subtract(ids) }
                } primaryAction: { ids in
                    open(ids)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search History")
        .toolbar {
            ToolbarItem {
                Picker("Profile", selection: Binding(get: { currentProfileID }, set: { profileID = $0 })) {
                    ForEach(store.profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }
                .pickerStyle(.menu)
                .help("Profile")
            }
            ToolbarItem {
                Button("Clear History…") { confirmsClear = true }
            }
        }
        .confirmationDialog("Clear history for \(profileName)?", isPresented: $confirmsClear) {
            Button("Last Hour", role: .destructive) { clear(since: .now.addingTimeInterval(-3600)) }
            Button("Today", role: .destructive) { clear(since: Calendar.current.startOfDay(for: .now)) }
            Button("All History", role: .destructive) { clear(since: nil) }
        } message: {
            Text("Cookies and logins stay. Only the list of visited pages is cleared.")
        }
        .frame(minWidth: 520, minHeight: 400)
        .navigationTitle("History")
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            FaviconView(url: entry.url, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                Text(entry.url.host() ?? entry.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.lastVisited, format: query.isEmpty ? .dateTime.hour().minute() : .dateTime.month().day().hour().minute())
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .tag(entry.id)
    }

    /// The picked profile, or the current space's.
    private var currentProfileID: Profile.ID? {
        profileID ?? store.selectedSpace?.profileID ?? store.profiles.first?.id
    }

    private var profileName: String {
        store.profiles.first { $0.id == currentProfileID }?.name ?? "this profile"
    }

    private func entries(_ ids: Set<HistoryEntry.ID>) -> [HistoryEntry] {
        pool.history.entries.filter { ids.contains($0.id) }
    }

    private func open(_ ids: Set<HistoryEntry.ID>) {
        let picked = entries(ids)
        guard let profile = picked.first?.profileID else { return }
        if store.selectedSpace?.profileID != profile, let space = store.spaces(using: profile).first {
            store.selectSpace(space.id)
        }
        for entry in picked { store.openTab(entry.url, title: entry.title) }
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("history") != true && $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    private func copy(_ ids: Set<HistoryEntry.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries(ids).map(\.url.absoluteString).joined(separator: "\n"), forType: .string)
    }

    private func clear(since date: Date?) {
        pool.history.clear(since: date, profileID: currentProfileID)
        selection = []
    }

    static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
