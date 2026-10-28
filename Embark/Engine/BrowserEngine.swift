import AppKit

/// The rendering engine behind every tab. Embark's UI only talks to these protocols, so the
/// Chromium (CEF) engine and the WebKit development engine are interchangeable.
@MainActor
protocol BrowserEngine: AnyObject {
    func makePage(url: URL, profile: Profile) -> BrowserPage
    /// Whether the engine runs Chrome extensions; without them the extensions button is hidden.
    var supportsExtensions: Bool { get }
    /// The Chrome extensions installed in a profile.
    func extensions(for profile: Profile) -> [InstalledExtension]
    /// Deletes a profile's logins, cookies, history and cache from disk. Its pages are closed.
    func removeData(for profile: Profile)
    /// Downloads from every page: `destination` picks where a new one is saved (nil cancels it)
    /// and `update` reports each change.
    func observeDownloads(destination: @escaping (String) -> URL?, update: @escaping (Download) -> Void)
    func cancelDownload(_ id: Download.ID)

    // Settings ▸ Privacy and Settings ▸ Profiles.
    /// Whether third-party cookies can be blocked and saved site permissions listed.
    var supportsSiteSettings: Bool { get }
    func setBlocksThirdPartyCookies(_ block: Bool)
    func siteExceptions(for profile: Profile) -> [SiteException]
    /// Forgets a site's saved permission, so the site asks again.
    func resetSiteException(_ exception: SiteException, for profile: Profile)
    /// Data that open pages hold on to, so it's removed the next time Embark starts.
    var browsingDataClearedAtLaunch: BrowsingData { get }
    /// Clears a profile's browsing data, apart from `browsingDataClearedAtLaunch`, which is
    /// queued for the next launch.
    func clearBrowsingData(_ data: BrowsingData, for profile: Profile, completion: @escaping @MainActor () -> Void)
}

extension BrowserEngine {
    var supportsExtensions: Bool { false }
    func extensions(for profile: Profile) -> [InstalledExtension] { [] }
    func observeDownloads(destination: @escaping (String) -> URL?, update: @escaping (Download) -> Void) {}
    func cancelDownload(_ id: Download.ID) {}
    var supportsSiteSettings: Bool { false }
    func setBlocksThirdPartyCookies(_ block: Bool) {}
    func siteExceptions(for profile: Profile) -> [SiteException] { [] }
    func resetSiteException(_ exception: SiteException, for profile: Profile) {}
    var browsingDataClearedAtLaunch: BrowsingData { [] }
}

/// What Clear Browsing Data removes from a profile.
struct BrowsingData: OptionSet {
    let rawValue: Int
    static let cookies = BrowsingData(rawValue: 1 << 0)
    static let cache = BrowsingData(rawValue: 1 << 1)
    /// Local storage, IndexedDB, service workers and other site data.
    static let storage = BrowsingData(rawValue: 1 << 2)
}

@MainActor
protocol BrowserPage: AnyObject {
    var view: NSView { get }
    var delegate: BrowserPageDelegate? { get set }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    /// Releases the renderer. The page is discarded afterwards.
    func close()

    // Page info. Engines without these keep the defaults below.
    var security: PageSecurity { get }
    /// A permission for the current page's site, kept by the page's profile.
    func permission(_ permission: SitePermission) -> PermissionValue
    /// What the profile uses for sites without their own setting.
    func defaultPermission(_ permission: SitePermission) -> PermissionValue
    func setPermission(_ permission: SitePermission, to value: PermissionValue)
    func setAudioMuted(_ muted: Bool)
    /// Mutes the tab from its speaker button, across the pages it loads.
    func setTabMuted(_ muted: Bool)
    func countCookies(_ completion: @escaping (Int) -> Void)
    /// Deletes the site's cookies and storage.
    func clearSiteData(_ completion: @escaping () -> Void)

    /// Highlights matches of `text`; results come back through the delegate.
    func find(_ text: String, forward: Bool, findNext: Bool)
    func stopFinding()
    /// Takes a full-screen video or element back into the page.
    func exitFullscreen()

    func stopLoading()
    /// 1 is 100%.
    var zoomFactor: Double { get set }
    func print()
    func showDevTools()
    /// Puts a saved login into the page's sign-in form.
    func fillLogin(username: String, password: String)
    /// Plays, pauses, skips or mutes what the page is playing (see MediaScript).
    func controlMedia(_ command: MediaCommand)
    /// Runs a JavaScript expression in the page's main frame, for reader mode and translation.
    /// `completion` gets its value (awaited if it's a promise) as JSON, or nil if it failed.
    func evaluate(_ script: String, completion: @escaping @MainActor (String?) -> Void)
}

extension BrowserPage {
    var security: PageSecurity { PageSecurity(isSecure: false, hasCertificateError: false, certificate: nil) }
    func permission(_ permission: SitePermission) -> PermissionValue { .default }
    func defaultPermission(_ permission: SitePermission) -> PermissionValue { .default }
    func setPermission(_ permission: SitePermission, to value: PermissionValue) {}
    func setAudioMuted(_ muted: Bool) {}
    func setTabMuted(_ muted: Bool) { setAudioMuted(muted) }
    func countCookies(_ completion: @escaping (Int) -> Void) { completion(0) }
    func clearSiteData(_ completion: @escaping () -> Void) { completion() }
    func find(_ text: String, forward: Bool, findNext: Bool) {}
    func stopFinding() {}
    func exitFullscreen() {}
    func stopLoading() {}
    var zoomFactor: Double {
        get { 1 }
        set {}
    }
    func print() {}
    func showDevTools() {}
    func fillLogin(username: String, password: String) {}
    func controlMedia(_ command: MediaCommand) {}
    func evaluate(_ script: String, completion: @escaping @MainActor (String?) -> Void) { completion(nil) }

    /// `evaluate` that gives up after `timeout`, e.g. when the page navigates away first.
    func evaluate(_ script: String, timeout: Duration = .seconds(10)) async -> String? {
        let wait = ScriptWait()
        let timer = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            wait.finish(nil)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                wait.continuation = continuation
                evaluate(script) { wait.finish($0) }
            }
        }
    }
}

/// Resumes an `evaluate` once, with its result or after the timeout.
@MainActor
private final class ScriptWait {
    var continuation: CheckedContinuation<String?, Never>?

    func finish(_ value: String?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
protocol BrowserPageDelegate: AnyObject {
    func page(_ page: BrowserPage, didChangeTitle title: String?, url: URL?)
    func page(_ page: BrowserPage, requestsNewTab url: URL)
    func page(_ page: BrowserPage, requestsPermission request: PermissionRequest)
    func page(_ page: BrowserPage, dismissedPermissionRequest id: UInt64)
    /// `active` counts from 1; 0 when no match is selected.
    func page(_ page: BrowserPage, didFindMatches count: Int, active: Int)
    func page(_ page: BrowserPage, didChangeFullscreen fullscreen: Bool)
    /// `progress` runs from 0 to 1 while loading.
    func page(_ page: BrowserPage, didChangeLoading isLoading: Bool, progress: Double)
    /// The page's own icon as PNG, or nil when it has none.
    func page(_ page: BrowserPage, didChangeFavicon png: Data?)
    func page(_ page: BrowserPage, requestsCredentials request: CredentialRequest)
    func page(_ page: BrowserPage, hitCertificateError warning: CertificateWarning)
    /// The page's renderer died, from a crash or from running out of memory.
    func page(_ page: BrowserPage, didCrashOutOfMemory outOfMemory: Bool)
    /// A message from the page's sign-in script (see LoginScript), as JSON.
    func page(_ page: BrowserPage, didPostLoginMessage message: String)
    /// A message from the page's media script (see MediaScript), as JSON.
    func page(_ page: BrowserPage, didPostMediaMessage message: String)
}

/// A site's sign-in prompt (HTTP authentication), answered once through `respond`.
struct CredentialRequest: Identifiable {
    let id = UUID()
    let host: String
    let realm: String?
    let isProxy: Bool
    /// nil cancels.
    let respond: (_ user: String?, _ password: String?) -> Void
}

/// A site whose certificate isn't trusted, answered once: true visits it anyway.
struct CertificateWarning: Identifiable {
    let id = UUID()
    let url: URL
    let description: String
    let respond: (Bool) -> Void
}

/// Per-site permissions shown in page info. Raw values match EMBSitePermission.
enum SitePermission: Int, CaseIterable, Identifiable {
    case camera, microphone, notifications, sound, autoPictureInPicture

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .notifications: "Notifications"
        case .sound: "Sound"
        case .autoPictureInPicture: "Automatic picture-in-picture"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "video"
        case .microphone: "mic"
        case .notifications: "bell"
        case .sound: "speaker.wave.2"
        case .autoPictureInPicture: "pip"
        }
    }

    /// Prompt wording: "wants to use your camera".
    /// Chromium's name for the content setting, as saved in a profile's Preferences.
    var chromiumName: String {
        switch self {
        case .camera: "media_stream_camera"
        case .microphone: "media_stream_mic"
        case .notifications: "notifications"
        case .sound: "sound"
        case .autoPictureInPicture: "auto_picture_in_picture"
        }
    }

    init?(chromiumName: String) {
        guard let match = Self.allCases.first(where: { $0.chromiumName == chromiumName }) else { return nil }
        self = match
    }

    var ask: String {
        switch self {
        case .camera: "use your camera"
        case .microphone: "use your microphone"
        case .notifications: "show notifications"
        case .sound: "play sound"
        case .autoPictureInPicture: "use picture-in-picture"
        }
    }
}

/// A permission's setting for a site. Raw values match EMBPermissionValue.
enum PermissionValue: Int {
    case `default`, allow, block, ask
}

struct PageCertificate {
    var subject: String
    var issuer: String
    var validFrom: Date
    var validUntil: Date
}

struct PageSecurity {
    var isSecure: Bool
    var hasCertificateError: Bool
    var certificate: PageCertificate?
}

/// A site asking for permissions, answered once through `respond`.
struct PermissionRequest: Identifiable {
    let id: UInt64
    let origin: String
    let permissions: [SitePermission]
    let respond: (Bool) -> Void

    var host: String { URL(string: origin)?.host() ?? origin }
}

enum Engines {
    @MainActor static func make() -> BrowserEngine {
        #if ENGINE_CEF
        return CEFEngine()
        #else
        return WebKitEngine()
        #endif
    }

    /// WebKit for protected video when the main engine is Chromium.
    @MainActor static func makeMediaEngine() -> BrowserEngine? {
        #if ENGINE_CEF
        return WebKitEngine()
        #else
        return nil
        #endif
    }
}
