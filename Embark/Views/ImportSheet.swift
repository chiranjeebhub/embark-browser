import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ General ▸ Import…: another browser's bookmarks become a folder of unloaded tabs
/// in a space.
struct ImportSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.chrome
    /// The other browser's profile folder, for Chrome, Brave and Edge.
    @State private var browserProfile = ""
    @State private var spaceID: Space.ID?
    @State private var file: URL?
    @State private var result: Result<ImportedFolder, BookmarkImportError>?
    @State private var imported: Int?

    enum Source: String, CaseIterable, Identifiable {
        case chrome, brave, edge, safari, file

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chrome: "Chrome"
            case .brave: "Brave"
            case .edge: "Edge"
            case .safari: "Safari"
            case .file: "HTML file"
            }
        }

        var symbol: String {
            switch self {
            case .chrome, .brave, .edge: "globe"
            case .safari: "safari"
            case .file: "doc.text"
            }
        }

        /// A Chromium browser's data folder.
        var chromiumFolder: URL? {
            let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
            switch self {
            case .chrome: return support.appending(path: "Google/Chrome")
            case .brave: return support.appending(path: "BraveSoftware/Brave-Browser")
            case .edge: return support.appending(path: "Microsoft Edge")
            case .safari, .file: return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Bookmarks").font(.system(size: 15, weight: .bold))
                Text("Each bookmark folder becomes a sidebar folder. Pages stay unloaded until you open them.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(Source.allCases) { item in
                    Button { pick(item) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: item.symbol).font(.system(size: 20))
                            Text(item.title).font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .background(source == item ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 11))
                        .overlay {
                            if source == item { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.accentColor, lineWidth: 2) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            sourceDetail

            HStack {
                Text("Add to space").foregroundStyle(.secondary)
                Spacer()
                Picker("Add to space", selection: $spaceID) {
                    ForEach(store.spaces) { Text($0.name).tag(Space.ID?.some($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
            }

            preview

            HStack {
                Spacer()
                if let imported {
                    Text("Added \(imported) bookmarks").foregroundStyle(.secondary)
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Import", action: importNow)
                        .keyboardShortcut(.defaultAction)
                        .disabled(bookmarks == nil || spaceID == nil)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            spaceID = store.selectedSpaceID ?? store.spaces.first?.id
            pick(.chrome)
        }
    }

    private var bookmarks: ImportedFolder? {
        if case .success(let folder)? = result, folder.bookmarkCount > 0 { return folder }
        return nil
    }

    @ViewBuilder private var sourceDetail: some View {
        if let folder = source.chromiumFolder {
            let profiles = chromiumProfiles(in: folder)
            if profiles.isEmpty {
                Text("\(source.title) isn’t set up on this Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if profiles.count > 1 {
                HStack {
                    Text("\(source.title) profile").foregroundStyle(.secondary)
                    Spacer()
                    Picker("\(source.title) profile", selection: $browserProfile) {
                        ForEach(profiles, id: \.directory) { Text($0.name).tag($0.directory) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: browserProfile) { load() }
                }
            }
        } else if source == .safari, case .failure(.needsFullDiskAccess)? = result {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS keeps Safari’s bookmarks private. Turn on Embark in Full Disk Access, then try again.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("Open Privacy & Security Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                        .buttonStyle(.link)
                        Button("Try Again", action: load).buttonStyle(.link)
                    }
                }
            }
            .padding(12)
            .background(.yellow.opacity(0.1), in: .rect(cornerRadius: 10))
        } else if source == .file {
            HStack {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(file?.lastPathComponent ?? "No file chosen").lineLimit(1)
                Spacer()
                Button("Choose File…", action: chooseFile)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let bookmarks {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bookmarks.bookmarkCount) bookmarks in \(bookmarks.folderCount) folders")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Array(previewRows(bookmarks).prefix(7).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 7) {
                        Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text("\(row.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(row.level) * 18)
                    .frame(height: 22)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
        } else if case .failure(.unreadable)? = result {
            Text("Those bookmarks couldn’t be read.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if result != nil {
            Text("No bookmarks to import.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    /// The top folders and the ones inside them.
    private func previewRows(_ root: ImportedFolder) -> [(name: String, count: Int, level: Int)] {
        root.folders.flatMap { folder in
            [(folder.name, folder.bookmarkCount, 0)] + folder.folders.map { ($0.name, $0.bookmarkCount, 1) }
        }
    }

    private func chromiumProfiles(in folder: URL) -> [(directory: String, name: String)] {
        guard let data = try? Data(contentsOf: folder.appending(path: "Local State")) else { return [] }
        return BookmarkImport.chromiumProfiles(localState: data)
    }

    private func pick(_ item: Source) {
        source = item
        result = nil
        imported = nil
        if let folder = item.chromiumFolder {
            browserProfile = chromiumProfiles(in: folder).first?.directory ?? ""
        }
        if item == .file, file == nil { return }
        load()
    }

    private func load() {
        imported = nil
        switch source {
        case .chrome, .brave, .edge:
            guard let folder = source.chromiumFolder, !browserProfile.isEmpty,
                  let data = try? Data(contentsOf: folder.appending(path: browserProfile).appending(path: "Bookmarks")) else {
                result = .failure(.unreadable)
                return
            }
            result = Result { try BookmarkImport.chromium(data, name: source.title) }.mapError { _ in .unreadable }
        case .safari:
            let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Bookmarks.plist")
            // Safari always has the file, so failing to read it means no Full Disk Access.
            guard let data = try? Data(contentsOf: url) else { result = .failure(.needsFullDiskAccess); return }
            result = Result { try BookmarkImport.safari(data) }.mapError { _ in .unreadable }
        case .file:
            guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else {
                result = file == nil ? nil : .failure(.unreadable)
                return
            }
            result = .success(BookmarkImport.html(text, name: "Imported Bookmarks"))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a bookmarks file exported from a browser"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        file = url
        load()
    }

    private func importNow() {
        guard let bookmarks, let spaceID else { return }
        imported = store.importBookmarks(bookmarks, into: spaceID)
    }
}
