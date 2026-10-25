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
}

extension BrowserEngine {
    var supportsExtensions: Bool { false }
    func extensions(for profile: Profile) -> [InstalledExtension] { [] }
    func observeDownloads(destination: @escaping (String) -> URL?, update: @escaping (Download) -> Void) {}
    func cancelDownload(_ id: Download.ID) {}
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
    func countCookies(_ completion: @escaping (Int) -> Void)
    /// Deletes the site's cookies and storage.
    func clearSiteData(_ completion: @escaping () -> Void)
}

extension BrowserPage {
    var security: PageSecurity { PageSecurity(isSecure: false, hasCertificateError: false, certificate: nil) }
    func permission(_ permission: SitePermission) -> PermissionValue { .default }
    func defaultPermission(_ permission: SitePermission) -> PermissionValue { .default }
    func setPermission(_ permission: SitePermission, to value: PermissionValue) {}
    func setAudioMuted(_ muted: Bool) {}
    func countCookies(_ completion: @escaping (Int) -> Void) { completion(0) }
    func clearSiteData(_ completion: @escaping () -> Void) { completion() }
}

@MainActor
protocol BrowserPageDelegate: AnyObject {
    func page(_ page: BrowserPage, didChangeTitle title: String?, url: URL?)
    func page(_ page: BrowserPage, requestsNewTab url: URL)
    func page(_ page: BrowserPage, requestsPermission request: PermissionRequest)
    func page(_ page: BrowserPage, dismissedPermissionRequest id: UInt64)
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
}
