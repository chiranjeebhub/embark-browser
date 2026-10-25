import Foundation

/// Bookmarks read from another browser, as a tree of folders.
struct ImportedFolder: Equatable {
    var name: String
    var bookmarks: [ImportedBookmark] = []
    var folders: [ImportedFolder] = []

    /// Bookmarks here and in every subfolder.
    var bookmarkCount: Int { bookmarks.count + folders.reduce(0) { $0 + $1.bookmarkCount } }

    /// Folders under this one, at any depth.
    var folderCount: Int { folders.reduce(folders.count) { $0 + $1.folderCount } }

    /// Drops folders with no bookmarks anywhere inside.
    func pruned() -> ImportedFolder {
        var copy = self
        copy.folders = folders.map { $0.pruned() }.filter { $0.bookmarkCount > 0 }
        return copy
    }
}

struct ImportedBookmark: Equatable {
    var title: String
    var url: URL
}

enum BookmarkImportError: LocalizedError {
    case unreadable
    /// macOS keeps Safari's files private until Embark has Full Disk Access.
    case needsFullDiskAccess

    var errorDescription: String? {
        switch self {
        case .unreadable: "Those bookmarks couldn’t be read."
        case .needsFullDiskAccess: "Embark needs Full Disk Access to read Safari’s bookmarks."
        }
    }
}

/// Parsers for the bookmark files browsers keep. Only http and https bookmarks are kept.
enum BookmarkImport {
    // MARK: Chrome, Brave, Edge

    /// A Chromium `Bookmarks` file. Its roots (Bookmarks Bar, Other Bookmarks, Mobile
    /// Bookmarks) become the top folders.
    static func chromium(_ data: Data, name: String) throws -> ImportedFolder {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { throw BookmarkImportError.unreadable }
        var result = ImportedFolder(name: name)
        for key in ["bookmark_bar", "other", "synced"] {
            guard let node = roots[key] as? [String: Any] else { continue }
            result.folders.append(chromiumFolder(node))
        }
        return result.pruned()
    }

    private static func chromiumFolder(_ node: [String: Any]) -> ImportedFolder {
        var folder = ImportedFolder(name: node["name"] as? String ?? "")
        for child in node["children"] as? [[String: Any]] ?? [] {
            switch child["type"] as? String {
            case "url":
                if let bookmark = bookmark(title: child["name"] as? String, url: child["url"] as? String) {
                    folder.bookmarks.append(bookmark)
                }
            case "folder":
                folder.folders.append(chromiumFolder(child))
            default:
                break
            }
        }
        return folder
    }

    /// A Chromium browser's profiles from its `Local State` file: folder name and display
    /// name, in the order the browser lists them.
    static func chromiumProfiles(localState data: Data) -> [(directory: String, name: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [] }
        let order = ((root["profile"] as? [String: Any])?["profiles_order"] as? [String]) ?? []
        let directories = cache.keys.sorted { a, b in
            let i = order.firstIndex(of: a) ?? .max, j = order.firstIndex(of: b) ?? .max
            return i != j ? i < j : a.localizedStandardCompare(b) == .orderedAscending
        }
        return directories.map { directory in
            let info = cache[directory] as? [String: Any]
            return (directory, (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory)
        }
    }

    // MARK: Safari

    /// Safari's `Bookmarks.plist`. The Reading List is kept as a folder of its own.
    static func safari(_ data: Data) throws -> ImportedFolder {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw BookmarkImportError.unreadable }
        var result = safariFolder(root)
        result.name = "Safari"
        return result.pruned()
    }

    private static func safariFolder(_ node: [String: Any]) -> ImportedFolder {
        let title = node["Title"] as? String ?? ""
        var folder = ImportedFolder(name: safariFolderNames[title] ?? title)
        for child in node["Children"] as? [[String: Any]] ?? [] {
            switch child["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                let title = (child["URIDictionary"] as? [String: Any])?["title"] as? String
                if let bookmark = bookmark(title: title, url: child["URLString"] as? String) {
                    folder.bookmarks.append(bookmark)
                }
            case "WebBookmarkTypeList":
                folder.folders.append(safariFolder(child))
            default:
                break
            }
        }
        return folder
    }

    private static let safariFolderNames = [
        "BookmarksBar": "Favorites", "BookmarksMenu": "Bookmarks Menu", "com.apple.ReadingList": "Reading List",
    ]

    // MARK: Exported HTML

    /// The Netscape bookmark file every browser exports: `<DT><H3>` starts a folder whose
    /// contents follow in a `<DL>`, and `<DT><A HREF>` is a bookmark.
    static func html(_ text: String, name: String) -> ImportedFolder {
        var stack = [ImportedFolder(name: name)]
        var pendingFolder: String?
        let pattern = try! NSRegularExpression(
            pattern: #"<h3[^>]*>(.*?)</h3>|<a\s[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>|<dl[^>]*>|</dl>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range).lowercased()
            if match.range(at: 1).location != NSNotFound {
                pendingFolder = decodeEntities(ns.substring(with: match.range(at: 1)))
            } else if match.range(at: 2).location != NSNotFound {
                let title = decodeEntities(ns.substring(with: match.range(at: 3)))
                if let bookmark = bookmark(title: title, url: decodeEntities(ns.substring(with: match.range(at: 2)))) {
                    stack[stack.count - 1].bookmarks.append(bookmark)
                }
            } else if token.hasPrefix("</") {
                // Closing a folder's list hands it to its parent; the outermost list stays.
                if stack.count > 1 {
                    let done = stack.removeLast()
                    stack[stack.count - 1].folders.append(done)
                }
            } else if let folder = pendingFolder {
                stack.append(ImportedFolder(name: folder))
                pendingFolder = nil
            }
        }
        while stack.count > 1 {
            let done = stack.removeLast()
            stack[stack.count - 1].folders.append(done)
        }
        return stack[0].pruned()
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bookmark(title: String?, url: String?) -> ImportedBookmark? {
        guard let url = url.flatMap(URL.init(string:)), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ImportedBookmark(title: title.isEmpty ? (url.host() ?? url.absoluteString) : title, url: url)
    }
}

extension Space {
    /// Adds imported bookmarks as a collapsed folder at the end of the tab list. Each bookmark
    /// becomes an unloaded tab, so nothing loads until it's opened. Folders nested deeper than
    /// `Folder.maxDepth` have their bookmarks put in the deepest folder allowed. Returns the
    /// number of tabs added.
    @discardableResult
    mutating func importBookmarks(_ root: ImportedFolder) -> Int {
        guard root.bookmarkCount > 0 else { return 0 }
        let start = tabs.count
        add(root, in: nil, depth: 1)
        return tabs.count - start
    }

    private mutating func add(_ imported: ImportedFolder, in parent: Folder.ID?, depth: Int) {
        let id: Folder.ID
        if depth > Folder.maxDepth, let parent {
            id = parent
        } else {
            let folder = Folder(name: imported.name.isEmpty ? Folder.defaultName : imported.name, parentID: parent, isExpanded: false)
            folders = allFolders + [folder]
            id = folder.id
        }
        tabs += imported.bookmarks.map { BrowserTab(title: $0.title, url: $0.url, folderID: id, isUnloaded: true) }
        for child in imported.folders { add(child, in: id, depth: depth + 1) }
    }
}
