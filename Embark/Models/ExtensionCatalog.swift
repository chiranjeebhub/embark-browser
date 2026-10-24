import Foundation

/// A Chrome extension installed in a profile.
struct InstalledExtension: Identifiable, Hashable {
    let id: String
    let name: String
    /// The toolbar icon, else the extension's largest icon.
    let iconFile: URL?
    /// The page Chrome shows when the toolbar button is clicked; nil when there is none.
    let popupURL: URL?
    let optionsURL: URL?
    let isEnabled: Bool
}

/// Reads the extensions Chromium installed into a profile folder. CEF has no API that lists
/// them, so this reads what Chromium keeps on disk: `Secure Preferences` and `Preferences`
/// list each extension with its folder, and the folder holds its manifest.
enum ExtensionCatalog {
    static func extensions(inProfile directory: URL, languages: [String] = Locale.preferredLanguages) -> [InstalledExtension] {
        var settings: [String: [String: Any]] = [:]
        // Chrome keeps Web Store extensions in Secure Preferences; read it last so it wins.
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: directory.appending(path: file)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = (root["extensions"] as? [String: Any])?["settings"] as? [String: Any] else { continue }
            for (id, entry) in entries {
                guard let entry = entry as? [String: Any] else { continue }
                settings[id, default: [:]].merge(entry) { _, new in new }
            }
        }
        return settings.compactMap { id, entry in
            read(id: id, entry: entry, profile: directory, languages: languages)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Chromium's own extensions (the PDF viewer, the Web Store) aren't shown.
    private static let hiddenLocations: Set<Int> = [5, 10]

    private static func read(id: String, entry: [String: Any], profile: URL, languages: [String]) -> InstalledExtension? {
        if let location = entry["location"] as? Int, hiddenLocations.contains(location) { return nil }
        guard let path = entry["path"] as? String, !path.isEmpty else { return nil }
        // Web Store extensions are stored relative to the profile's Extensions folder;
        // unpacked ones by their full path.
        let folder = path.hasPrefix("/")
            ? URL(filePath: path, directoryHint: .isDirectory)
            : profile.appending(path: "Extensions", directoryHint: .isDirectory).appending(path: path, directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["theme"] == nil, manifest["app"] == nil,
              let rawName = manifest["name"] as? String else { return nil }

        let action = (manifest["action"] ?? manifest["browser_action"] ?? manifest["page_action"]) as? [String: Any]
        let options = (manifest["options_ui"] as? [String: Any])?["page"] as? String ?? manifest["options_page"] as? String
        return InstalledExtension(
            id: id,
            name: localized(rawName, manifest: manifest, folder: folder, languages: languages),
            iconFile: icon(action?["default_icon"] ?? manifest["icons"], in: folder),
            popupURL: page(action?["default_popup"] as? String, id: id),
            optionsURL: page(options, id: id),
            isEnabled: isEnabled(entry))
    }

    /// Off when Chromium recorded a reason (a bitmask in older builds, a list in newer ones), or
    /// the old `state` key says disabled.
    static func isEnabled(_ entry: [String: Any]) -> Bool {
        if let state = entry["state"] as? Int, state == 0 { return false }
        switch entry["disable_reasons"] {
        case let mask as Int: return mask == 0
        case let reasons as [Any]: return reasons.isEmpty
        default: return true
        }
    }

    private static func page(_ path: String?, id: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "chrome-extension://\(id)/\(path.trimmingPrefix("/"))")
    }

    /// The largest icon up to 128px, else the smallest one.
    private static func icon(_ value: Any?, in folder: URL) -> URL? {
        let path: String?
        switch value {
        case let single as String: path = single
        case let sizes as [String: Any]:
            let paths = sizes.compactMap { key, value -> (Int, String)? in
                guard let size = Int(key), let path = value as? String else { return nil }
                return (size, path)
            }
            .sorted { $0.0 < $1.0 }
            path = (paths.last { $0.0 <= 128 } ?? paths.first)?.1
        default: path = nil
        }
        guard let path, !path.isEmpty else { return nil }
        return folder.appending(path: String(path.trimmingPrefix("/")))
    }

    /// Resolves a `__MSG_key__` name from the extension's `_locales`, in the user's languages
    /// first, then the manifest's default locale. Message keys ignore case.
    static func localized(_ name: String, manifest: [String: Any], folder: URL, languages: [String]) -> String {
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__"), name.count > 8 else { return name }
        let key = name.dropFirst(6).dropLast(2).lowercased()
        var locales: [String] = []
        for language in languages {
            let code = language.replacingOccurrences(of: "-", with: "_")
            locales.append(code)
            if let base = code.split(separator: "_").first { locales.append(String(base)) }
        }
        if let fallback = manifest["default_locale"] as? String { locales.append(fallback) }
        for locale in locales {
            let file = folder.appending(path: "_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: file),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (messageKey, value) in messages where messageKey.lowercased() == key {
                if let message = (value as? [String: Any])?["message"] as? String { return message }
            }
        }
        return name
    }
}
