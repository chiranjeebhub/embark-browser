import Foundation
import Testing

/// Reading a profile's extensions the way Chromium leaves them on disk: Web Store and
/// unpacked extensions, Chromium's own ones hidden, disabled ones, popups, icons and names.
struct ExtensionCatalogTests {
    private let profile: URL

    init() throws {
        profile = FileManager.default.temporaryDirectory.appending(path: "ExtensionCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    }

    private func write(_ json: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    private func install(_ id: String, version: String = "1.0_0", manifest: [String: Any]) throws {
        try write(manifest, to: profile.appending(path: "Extensions/\(id)/\(version)/manifest.json"))
    }

    private func preferences(_ settings: [String: Any], file: String = "Secure Preferences") throws {
        try write(["extensions": ["settings": settings]], to: profile.appending(path: file))
    }

    @Test func readsWebStoreExtensionWithPopupAndIcon() throws {
        try install("abc", manifest: [
            "name": "Ad block", "manifest_version": 3,
            "action": ["default_popup": "popup.html", "default_icon": ["16": "i16.png", "48": "i48.png", "256": "i256.png"]],
            "options_ui": ["page": "/options.html"],
        ])
        try preferences(["abc": ["location": 1, "path": "abc/1.0_0"]])
        let all = ExtensionCatalog.extensions(inProfile: profile)
        let ext = try #require(all.first)
        #expect(all.count == 1)
        #expect(ext.name == "Ad block")
        #expect(ext.popupURL?.absoluteString == "chrome-extension://abc/popup.html")
        #expect(ext.optionsURL?.absoluteString == "chrome-extension://abc/options.html")
        #expect(ext.iconFile?.lastPathComponent == "i48.png")
        #expect(ext.isEnabled)
    }

    @Test func hidesComponentExtensionsThemesAndApps() throws {
        try install("pdf", manifest: ["name": "PDF Viewer"])
        try install("theme", manifest: ["name": "Dark theme", "theme": [:]])
        try install("app", manifest: ["name": "Old app", "app": [:]])
        try preferences(["pdf": ["location": 5, "path": "pdf/1.0_0"],
                         "theme": ["location": 1, "path": "theme/1.0_0"],
                         "app": ["location": 1, "path": "app/1.0_0"]])
        #expect(ExtensionCatalog.extensions(inProfile: profile).isEmpty)
    }

    @Test func readsUnpackedExtensionFromItsFullPath() throws {
        let folder = profile.appending(path: "Unpacked/dev")
        try write(["name": "Dev tool", "browser_action": ["default_icon": "icon.png"]], to: folder.appending(path: "manifest.json"))
        try preferences(["dev": ["location": 4, "path": folder.path]], file: "Preferences")
        let ext = try #require(ExtensionCatalog.extensions(inProfile: profile).first)
        #expect(ext.name == "Dev tool")
        #expect(ext.popupURL == nil)
        #expect(ext.iconFile?.lastPathComponent == "icon.png")
    }

    @Test func disabledInEitherFormat() {
        #expect(!ExtensionCatalog.isEnabled(["disable_reasons": 1]))
        #expect(!ExtensionCatalog.isEnabled(["disable_reasons": [1]]))
        #expect(!ExtensionCatalog.isEnabled(["state": 0]))
        #expect(ExtensionCatalog.isEnabled(["disable_reasons": 0]))
        #expect(ExtensionCatalog.isEnabled(["disable_reasons": []]))
        #expect(ExtensionCatalog.isEnabled([:]))
    }

    @Test func localizesNameFromLocales() throws {
        try install("loc", manifest: ["name": "__MSG_appName__", "default_locale": "en"])
        let folder = profile.appending(path: "Extensions/loc/1.0_0")
        try write(["appname": ["message": "Translate"]], to: folder.appending(path: "_locales/en/messages.json"))
        try write(["appName": ["message": "Übersetzen"]], to: folder.appending(path: "_locales/de/messages.json"))
        try preferences(["loc": ["path": "loc/1.0_0"]])
        #expect(ExtensionCatalog.extensions(inProfile: profile, languages: ["fr-FR"]).first?.name == "Translate")
        #expect(ExtensionCatalog.extensions(inProfile: profile, languages: ["de-DE"]).first?.name == "Übersetzen")
    }

    @Test func sortsByName() throws {
        try install("b", manifest: ["name": "beta"])
        try install("a", manifest: ["name": "Alpha"])
        try preferences(["b": ["path": "b/1.0_0"], "a": ["path": "a/1.0_0"]])
        #expect(ExtensionCatalog.extensions(inProfile: profile).map(\.name) == ["Alpha", "beta"])
    }
}
