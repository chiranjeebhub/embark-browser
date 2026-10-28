#import "CEFBridge.h"

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_cookie.h"
#include "include/cef_download_handler.h"
#include "include/cef_find_handler.h"
#include "include/cef_navigation_entry.h"
#include "include/cef_image.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_ssl_info.h"
#include "include/cef_ssl_status.h"
#include "include/cef_x509_certificate.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_values.h"
#include "include/wrapper/cef_library_loader.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <map>
#include <objc/runtime.h>
#include <string>
#include <vector>

// MARK: - Application

// CEF needs NSApp to implement CefAppProtocol. SwiftUI's App lifecycle creates its own
// NSApplication subclass and ignores NSPrincipalClass, so the methods are added at runtime.
namespace {

BOOL gHandlingSendEvent = NO;
IMP gOriginalSendEvent = nullptr;

void SendEventTrackingCEF(id self, SEL _cmd, NSEvent *event) {
    CefScopedSendingEvent sendingEventScoper;
    ((void (*)(id, SEL, NSEvent *))gOriginalSendEvent)(self, _cmd, event);
}

void InstallCefAppProtocol(NSApplication *app) {
    Class cls = [app class];
    if ([cls conformsToProtocol:@protocol(CefAppProtocol)]) return;
    class_addMethod(cls, @selector(isHandlingSendEvent),
                    imp_implementationWithBlock(^BOOL(id) { return gHandlingSendEvent; }), "B@:");
    class_addMethod(cls, @selector(setHandlingSendEvent:),
                    imp_implementationWithBlock(^(id, BOOL handling) { gHandlingSendEvent = handling; }), "v@:B");
    Method sendEvent = class_getInstanceMethod(cls, @selector(sendEvent:));
    gOriginalSendEvent = method_getImplementation(sendEvent);
    // Add an override on this class so NSApplication itself stays untouched; replace only if
    // the class already defines its own sendEvent:.
    if (!class_addMethod(cls, @selector(sendEvent:), (IMP)SendEventTrackingCEF, method_getTypeEncoding(sendEvent))) {
        method_setImplementation(sendEvent, (IMP)SendEventTrackingCEF);
    }
    class_addProtocol(cls, @protocol(CefAppProtocol));
}

}  // namespace

// MARK: - Runtime and message pump

namespace {

CefScopedLibraryLoader *gLibraryLoader = nullptr;
// Every open browser, so they can all be closed before CefShutdown (which requires it).
std::map<int, CefRefPtr<CefBrowser>> gBrowsers;
void (^gAllBrowsersClosed)(void) = nil;

// Embark keeps AppKit's run loop and drives CEF with an external message pump, as cefclient
// does: one timer for the next piece of work, so a busy page asking for work thousands of
// times a second queues one job instead of thousands that crowd out clicks and scrolling.
// Work CEF asks for while it is already running is done right after it returns.

// No longer than this between pumps, in case CEF doesn't ask (cefclient uses the same).
constexpr int64_t kMaxPumpDelayMs = 1000 / 30;
NSTimer *gPumpTimer = nil;
bool gPumping = false;
bool gPumpReentered = false;
bool gPumpStopped = false;
// An immediate pump is already queued on the main thread.
std::atomic<bool> gImmediatePumpQueued{false};

void SchedulePump(int64_t delayMs);

void Pump() {
    if (gPumpStopped) return;
    if (gPumping) { gPumpReentered = true; return; }
    gPumping = true;
    gPumpReentered = false;
    CefDoMessageLoopWork();
    gPumping = false;
    if (gPumpReentered) {
        SchedulePump(0);
    } else if (!gPumpTimer) {
        SchedulePump(kMaxPumpDelayMs);
    }
}

// Main thread. Keeps whichever of the pending and the new deadline comes first.
void ArmPumpTimer(int64_t delayMs) {
    if (gPumpStopped) return;
    NSTimeInterval delay = MIN(delayMs, kMaxPumpDelayMs) / 1000.0;
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:delay];
    if (gPumpTimer && [gPumpTimer.fireDate compare:fireDate] != NSOrderedDescending) return;
    [gPumpTimer invalidate];
    gPumpTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *) {
        gPumpTimer = nil;
        Pump();
    }];
    // Common modes, so pages keep running while a window is resized or a menu is open.
    [NSRunLoop.mainRunLoop addTimer:gPumpTimer forMode:NSRunLoopCommonModes];
}

// Any thread.
void SchedulePump(int64_t delayMs) {
    if (delayMs <= 0) {
        if (gImmediatePumpQueued.exchange(true)) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            gImmediatePumpQueued = false;
            [gPumpTimer invalidate];
            gPumpTimer = nil;
            Pump();
        });
    } else if (NSThread.isMainThread) {
        ArmPumpTimer(delayMs);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ ArmPumpTimer(delayMs); });
    }
}

class EmbarkApp : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

    void OnScheduleMessagePumpWork(int64_t delayMs) override { SchedulePump(delayMs); }

private:
    IMPLEMENT_REFCOUNTING(EmbarkApp);
};

}  // namespace

@implementation EMBCEFRuntime

+ (BOOL)startWithCacheRoot:(NSURL *)cacheRoot {
    InstallCefAppProtocol(NSApplication.sharedApplication);
    gLibraryLoader = new CefScopedLibraryLoader();
    if (!gLibraryLoader->LoadInMain()) return NO;

    CefMainArgs args(0, nullptr);
    CefSettings settings;
    settings.external_message_pump = true;
    // The macOS sandbox needs cef_sandbox linked into every helper; turned off until then.
    settings.no_sandbox = true;
    CefString(&settings.root_cache_path) = cacheRoot.path.UTF8String;
    CefString(&settings.cache_path) = [cacheRoot URLByAppendingPathComponent:@"Default"].path.UTF8String;
    // Our own keychain item for the cookie and password encryption key, instead of sharing
    // "Chromium Safe Storage" with a real Chromium install.
    CefString(&settings.keychain_service_name) = "Embark Safe Storage";
    CefString(&settings.keychain_account_name) = "Embark";

    if (!CefInitialize(args, settings, new EmbarkApp(), nullptr)) return NO;

    SchedulePump(0);
    return YES;
}

+ (BOOL)hasOpenBrowsers { return !gBrowsers.empty(); }

+ (void)closeAllBrowsers:(void (^)(void))completion {
    if (gBrowsers.empty()) { dispatch_async(dispatch_get_main_queue(), completion); return; }
    gAllBrowsersClosed = [completion copy];
    auto browsers = gBrowsers;
    for (auto &entry : browsers) entry.second->GetHost()->CloseBrowser(true);
}

+ (void)shutdown {
    gPumpStopped = true;
    [gPumpTimer invalidate];
    gPumpTimer = nil;
    CefShutdown();
    delete gLibraryLoader;
    gLibraryLoader = nullptr;
}

@end

// MARK: - Browser

@implementation EMBCEFCertificate
@end

@implementation EMBCEFDownload
@end

@interface EMBCEFBrowser ()
- (instancetype)initWithURL:(NSURL *)url context:(CefRefPtr<CefRequestContext>)context;
- (void)handleTitle:(NSString *)title;
- (void)handleURL:(NSString *)url;
- (void)handlePopup:(NSString *)url;
- (void)handleNavigationStateBack:(BOOL)back forward:(BOOL)forward;
- (void)handleLoading:(BOOL)isLoading progress:(double)progress;
- (void)handleFavicon:(nullable NSData *)png;
- (void)handleCredentialsForHost:(NSString *)host realm:(nullable NSString *)realm isProxy:(BOOL)isProxy
                         respond:(void (^)(NSString *, NSString *))respond;
- (void)handleCertificateErrorForURL:(NSURL *)url description:(NSString *)description respond:(void (^)(BOOL))respond;
- (void)handleCreated:(CefRefPtr<CefBrowser>)browser;
- (void)handlePermissionRequest:(NSArray<NSNumber *> *)permissions origin:(NSString *)origin
                      requestID:(uint64_t)requestID respond:(void (^)(BOOL))respond;
- (void)handlePermissionDismissed:(uint64_t)requestID;
- (void)handleFindCount:(int)count active:(int)active;
- (void)handleFullscreen:(BOOL)fullscreen;
- (void)handleRenderProcessTerminatedOutOfMemory:(BOOL)outOfMemory;
- (void)handleLoginMessage:(NSString *)message;
- (void)handleMediaMessage:(NSString *)message;
@end

namespace {

cef_content_setting_types_t ContentType(EMBSitePermission permission) {
    switch (permission) {
    case EMBSitePermissionCamera: return CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA;
    case EMBSitePermissionMicrophone: return CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC;
    case EMBSitePermissionNotifications: return CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS;
    case EMBSitePermissionSound: return CEF_CONTENT_SETTING_TYPE_SOUND;
    case EMBSitePermissionAutoPictureInPicture: return CEF_CONTENT_SETTING_TYPE_AUTO_PICTURE_IN_PICTURE;
    }
}

cef_content_setting_values_t ContentValue(EMBPermissionValue value) {
    switch (value) {
    case EMBPermissionValueDefault: return CEF_CONTENT_SETTING_VALUE_DEFAULT;
    case EMBPermissionValueAllow: return CEF_CONTENT_SETTING_VALUE_ALLOW;
    case EMBPermissionValueBlock: return CEF_CONTENT_SETTING_VALUE_BLOCK;
    case EMBPermissionValueAsk: return CEF_CONTENT_SETTING_VALUE_ASK;
    }
}

EMBPermissionValue PermissionValue(cef_content_setting_values_t value) {
    switch (value) {
    case CEF_CONTENT_SETTING_VALUE_ALLOW: return EMBPermissionValueAllow;
    case CEF_CONTENT_SETTING_VALUE_BLOCK: return EMBPermissionValueBlock;
    case CEF_CONTENT_SETTING_VALUE_ASK: return EMBPermissionValueAsk;
    default: return EMBPermissionValueDefault;
    }
}

NSDate *DateFromBaseTime(const CefBaseTime &time) {
    // CefBaseTime counts microseconds since 1601-01-01.
    return [NSDate dateWithTimeIntervalSince1970:(double)time.val / 1e6 - 11644473600.0];
}

/// "accounts.google.com" -> "google.com", "news.bbc.co.uk" -> "bbc.co.uk". A heuristic in place
/// of the public suffix list, used to find a site's cookies.
std::string RegistrableDomain(const std::string &host) {
    std::vector<std::string> labels;
    size_t start = 0, dot;
    while ((dot = host.find('.', start)) != std::string::npos) { labels.push_back(host.substr(start, dot - start)); start = dot + 1; }
    labels.push_back(host.substr(start));
    if (labels.size() <= 2) return host;
    size_t keep = (labels.back().size() == 2 && labels[labels.size() - 2].size() <= 3) ? 3 : 2;
    std::string domain;
    for (size_t i = labels.size() - std::min(keep, labels.size()); i < labels.size(); ++i) domain += (domain.empty() ? "" : ".") + labels[i];
    return domain;
}

/// Counts the cookies for a URL and reports the total once the visit is over.
class CookieCounter : public CefCookieVisitor {
public:
    explicit CookieCounter(void (^completion)(NSInteger)) : completion_(completion) {}
    ~CookieCounter() override {
        auto completion = completion_;
        NSInteger count = count_;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(count); });
    }
    bool Visit(const CefCookie &, int, int total, bool &) override {
        count_ = total;
        return false;
    }

private:
    void (^completion_)(NSInteger);
    NSInteger count_ = 0;
    IMPLEMENT_REFCOUNTING(CookieCounter);
};

/// Deletes every cookie whose domain is `site` or under it, then calls back.
class CookieDeleter : public CefCookieVisitor {
public:
    CookieDeleter(std::string site, void (^completion)(void)) : site_(std::move(site)), completion_(completion) {}
    ~CookieDeleter() override { dispatch_async(dispatch_get_main_queue(), completion_); }
    bool Visit(const CefCookie &cookie, int, int, bool &deleteCookie) override {
        std::string domain = CefString(&cookie.domain).ToString();
        if (!domain.empty() && domain[0] == '.') domain.erase(0, 1);
        deleteCookie = domain == site_ ||
                       (domain.size() > site_.size() && domain.compare(domain.size() - site_.size() - 1, std::string::npos, "." + site_) == 0);
        return true;
    }

private:
    std::string site_;
    void (^completion_)(void);
    IMPLEMENT_REFCOUNTING(CookieDeleter);
};

// MARK: Downloads

// Chromium numbers downloads per profile, so Embark gives each its own id across profiles.
std::map<std::pair<std::string, uint32_t>, uint32_t> gDownloadIDs;
std::map<uint32_t, CefRefPtr<CefDownloadItemCallback>> gDownloadCallbacks;
uint32_t gNextDownloadID = 1;
__weak id<EMBCEFDownloadObserver> gDownloadObserver;

uint32_t DownloadID(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item) {
    std::string profile = browser ? browser->GetHost()->GetRequestContext()->GetCachePath().ToString() : "";
    auto key = std::make_pair(profile, item->GetId());
    auto found = gDownloadIDs.find(key);
    if (found != gDownloadIDs.end()) return found->second;
    return gDownloadIDs[key] = gNextDownloadID++;
}

EMBCEFDownload *DownloadSnapshot(uint32_t identifier, CefRefPtr<CefDownloadItem> item) {
    EMBCEFDownload *download = [EMBCEFDownload new];
    download.identifier = identifier;
    std::string url = item->GetOriginalUrl().ToString();
    download.url = url.empty() ? nil : [NSURL URLWithString:@(url.c_str())];
    std::string path = item->GetFullPath().ToString();
    download.fileURL = path.empty() ? nil : [NSURL fileURLWithPath:@(path.c_str())];
    download.fileName = download.fileURL ? download.fileURL.lastPathComponent : @(item->GetSuggestedFileName().ToString().c_str());
    download.receivedBytes = item->GetReceivedBytes();
    download.totalBytes = item->GetTotalBytes() > 0 ? item->GetTotalBytes() : -1;
    download.bytesPerSecond = item->GetCurrentSpeed();
    if (item->IsComplete()) download.state = EMBDownloadStateComplete;
    else if (item->IsCanceled()) download.state = EMBDownloadStateCanceled;
    else if (item->IsInterrupted()) download.state = EMBDownloadStateFailed;
    else download.state = EMBDownloadStateInProgress;
    return download;
}

// MARK: Context menu

enum ContextMenuCommand {
    kOpenLinkInNewTab = MENU_ID_USER_FIRST,
    kCopyLink,
    kOpenImageInNewTab,
    kSaveImage,
    kCopyImageAddress,
    kInspectElement,
};

void CopyToPasteboard(const std::string &text) {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:@(text.c_str()) forType:NSPasteboardTypeString];
}

void ForgetBrowser(CefRefPtr<CefBrowser> browser) {
    gBrowsers.erase(browser->GetIdentifier());
    if (gBrowsers.empty() && gAllBrowsersClosed) {
        auto completion = gAllBrowsersClosed;
        gAllBrowsersClosed = nil;
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

/// Developer tools open in their own window. Tracked so quitting waits for it to close.
class DevToolsClient : public CefClient, public CefLifeSpanHandler {
public:
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override { gBrowsers[browser->GetIdentifier()] = browser; }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { ForgetBrowser(browser); }

private:
    IMPLEMENT_REFCOUNTING(DevToolsClient);
};

// MARK: Page icons

/// Hands the downloaded icon to the page as PNG.
class FaviconReceiver : public CefDownloadImageCallback {
public:
    explicit FaviconReceiver(EMBCEFBrowser *owner) : owner_(owner) {}
    void OnDownloadImageFinished(const CefString &, int, CefRefPtr<CefImage> image) override {
        NSData *png = nil;
        if (image && !image->IsEmpty()) {
            int width = 0, height = 0;
            auto data = image->GetAsPNG(2, true, width, height);
            if (!data) data = image->GetAsPNG(1, true, width, height);
            if (data && data->GetSize() > 0) {
                NSMutableData *bytes = [NSMutableData dataWithLength:data->GetSize()];
                data->GetData(bytes.mutableBytes, data->GetSize(), 0);
                png = bytes;
            }
        }
        [owner_ handleFavicon:png];
    }

private:
    __weak EMBCEFBrowser *owner_;
    IMPLEMENT_REFCOUNTING(FaviconReceiver);
};

NSString *CertificateErrorDescription(cef_errorcode_t error) {
    switch (error) {
    case ERR_CERT_DATE_INVALID: return @"Its security certificate has expired or isn't valid yet.";
    case ERR_CERT_COMMON_NAME_INVALID: return @"Its security certificate is for a different site.";
    case ERR_CERT_AUTHORITY_INVALID: return @"Its security certificate isn't from an authority your Mac trusts.";
    case ERR_CERT_REVOKED: return @"Its security certificate has been revoked.";
    default: return @"Its security certificate isn't valid.";
    }
}

/// Media requests get ids above this, so they never collide with Chromium's prompt ids.
uint64_t gNextMediaRequestID = 1ull << 62;

class EmbarkClient : public CefClient,
                     public CefDisplayHandler,
                     public CefContextMenuHandler,
                     public CefDownloadHandler,
                     public CefFindHandler,
                     public CefLifeSpanHandler,
                     public CefLoadHandler,
                     public CefPermissionHandler,
                     public CefRequestHandler {
public:
    explicit EmbarkClient(EMBCEFBrowser *owner) : owner_(owner) {}

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

    // Camera and microphone: use the site's saved choice, otherwise ask with Embark's prompt
    // and save the answer in the profile.
    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, const CefString &origin,
                                        uint32_t requested, CefRefPtr<CefMediaAccessCallback> callback) override {
        uint32_t device = requested & (CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE);
        if (device == 0 || device != requested) return false;  // Screen capture keeps Chromium's handling.
        std::vector<cef_content_setting_types_t> types;
        NSMutableArray<NSNumber *> *permissions = [NSMutableArray array];
        if (requested & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) { types.push_back(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA); [permissions addObject:@(EMBSitePermissionCamera)]; }
        if (requested & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) { types.push_back(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC); [permissions addObject:@(EMBSitePermissionMicrophone)]; }
        auto context = browser->GetHost()->GetRequestContext();
        bool allAllowed = true, anyBlocked = false;
        for (auto type : types) {
            auto value = context->GetContentSetting(origin, origin, type);
            allAllowed &= value == CEF_CONTENT_SETTING_VALUE_ALLOW;
            anyBlocked |= value == CEF_CONTENT_SETTING_VALUE_BLOCK;
        }
        if (allAllowed) { callback->Continue(requested); return true; }
        if (anyBlocked || !owner_) { callback->Continue(CEF_MEDIA_PERMISSION_NONE); return true; }
        CefString savedOrigin = origin;
        [owner_ handlePermissionRequest:permissions origin:@(origin.ToString().c_str()) requestID:gNextMediaRequestID++
                                respond:^(BOOL allow) {
            for (auto type : types) {
                context->SetContentSetting(savedOrigin, savedOrigin, type,
                                           allow ? CEF_CONTENT_SETTING_VALUE_ALLOW : CEF_CONTENT_SETTING_VALUE_BLOCK);
            }
            callback->Continue(allow ? requested : CEF_MEDIA_PERMISSION_NONE);
        }];
        return true;
    }

    // Other prompts (notifications, and camera/mic through the Permissions API): Embark's
    // prompt instead of Chrome's bubble, which has no window to show in here. Chromium saves
    // the answer.
    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t promptID, const CefString &origin, uint32_t requested,
                                CefRefPtr<CefPermissionPromptCallback> callback) override {
        NSMutableArray<NSNumber *> *permissions = [NSMutableArray array];
        if (requested & CEF_PERMISSION_TYPE_CAMERA_STREAM) [permissions addObject:@(EMBSitePermissionCamera)];
        if (requested & CEF_PERMISSION_TYPE_MIC_STREAM) [permissions addObject:@(EMBSitePermissionMicrophone)];
        if (requested & CEF_PERMISSION_TYPE_NOTIFICATIONS) [permissions addObject:@(EMBSitePermissionNotifications)];
        if (permissions.count == 0 || !owner_) return false;
        [owner_ handlePermissionRequest:permissions origin:@(origin.ToString().c_str()) requestID:promptID respond:^(BOOL allow) {
            callback->Continue(allow ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
        }];
        return true;
    }

    void OnDismissPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t promptID, cef_permission_request_result_t) override {
        [owner_ handlePermissionDismissed:promptID];
    }

    void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override {
        [owner_ handleTitle:@(title.ToString().c_str())];
    }

    void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString &url) override {
        if (frame->IsMain()) [owner_ handleURL:@(url.ToString().c_str())];
    }

    void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool isLoading, bool canGoBack, bool canGoForward) override {
        [owner_ handleNavigationStateBack:canGoBack forward:canGoForward];
        [owner_ handleLoading:isLoading progress:isLoading ? 0.1 : 1];
    }

    void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
        if (browser->IsLoading()) [owner_ handleLoading:YES progress:progress];
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        gBrowsers[browser->GetIdentifier()] = browser;
        [owner_ handleCreated:browser];
    }

    // A tab is a child view of the shared window, so closing one must not send performClose:
    // to that window (CEF's default). Removing CEF's view instead finishes the close.
    bool DoClose(CefRefPtr<CefBrowser> browser) override {
        NSView *hostView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
        [hostView removeFromSuperview];
        return true;
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { ForgetBrowser(browser); }

    // Popups and target=_blank become tabs in the same space instead of new windows.
    bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString &targetURL,
                       const CefString &, WindowOpenDisposition, bool, const CefPopupFeatures &,
                       CefWindowInfo &, CefRefPtr<CefClient> &, CefBrowserSettings &,
                       CefRefPtr<CefDictionaryValue> &, bool *) override {
        [owner_ handlePopup:@(targetURL.ToString().c_str())];
        return true;
    }

    // Downloads go straight to the folder Embark picks, without a save panel, like Arc.
    bool OnBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem>, const CefString &suggestedName,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override {
        NSURL *destination = [gDownloadObserver cefDownloadDestinationForSuggestedName:@(suggestedName.ToString().c_str())];
        if (!destination) return false;
        callback->Continue(destination.path.UTF8String, false);
        return true;
    }

    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                           CefRefPtr<CefDownloadItemCallback> callback) override {
        if (!item->IsValid()) return;
        uint32_t identifier = DownloadID(browser, item);
        if (item->IsComplete() || item->IsCanceled() || item->IsInterrupted()) gDownloadCallbacks.erase(identifier);
        else gDownloadCallbacks[identifier] = callback;
        [gDownloadObserver cefDownloadDidUpdate:DownloadSnapshot(identifier, item)];
    }

    // The page's own icon, rather than asking a web service for it.
    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString> &urls) override {
        if (urls.empty()) { [owner_ handleFavicon:nil]; return; }
        browser->GetHost()->DownloadImage(urls.front(), true, 64, false, new FaviconReceiver(owner_));
    }

    bool GetAuthCredentials(CefRefPtr<CefBrowser>, const CefString &, bool isProxy, const CefString &host, int,
                            const CefString &realm, const CefString &, CefRefPtr<CefAuthCallback> callback) override {
        if (!owner_) return false;
        std::string realmText = realm.ToString();
        [owner_ handleCredentialsForHost:@(host.ToString().c_str())
                                   realm:realmText.empty() ? nil : @(realmText.c_str())
                                 isProxy:isProxy
                                 respond:^(NSString *user, NSString *password) {
            if (user && password) callback->Continue(user.UTF8String, password.UTF8String);
            else callback->Cancel();
        }];
        return true;
    }

    bool OnCertificateError(CefRefPtr<CefBrowser>, cef_errorcode_t error, const CefString &requestURL,
                            CefRefPtr<CefSSLInfo>, CefRefPtr<CefCallback> callback) override {
        NSURL *url = [NSURL URLWithString:@(requestURL.ToString().c_str())];
        if (!owner_ || !url) return false;
        [owner_ handleCertificateErrorForURL:url description:CertificateErrorDescription(error) respond:^(BOOL proceed) {
            if (proceed) callback->Continue();
            else callback->Cancel();
        }];
        return true;
    }

    void OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, int) override {
        NSString *script = owner_.documentScript;
        if (frame->IsMain() && script.length) frame->ExecuteJavaScript(script.UTF8String, frame->GetURL(), 0);
    }

    bool OnConsoleMessage(CefRefPtr<CefBrowser>, cef_log_severity_t, const CefString &message, const CefString &, int) override {
        NSString *text = @(message.ToString().c_str());
        NSString *login = owner_.loginMessagePrefix, *media = owner_.mediaMessagePrefix;
        if (login.length && [text hasPrefix:login]) {
            [owner_ handleLoginMessage:[text substringFromIndex:login.length]];
            return true;
        }
        if (media.length && [text hasPrefix:media]) {
            [owner_ handleMediaMessage:[text substringFromIndex:media.length]];
            return true;
        }
        return false;
    }

    void OnRenderProcessTerminated(CefRefPtr<CefBrowser>, TerminationStatus status, int, const CefString &) override {
        [owner_ handleRenderProcessTerminatedOutOfMemory:status == TS_PROCESS_OOM];
    }

    void OnFullscreenModeChange(CefRefPtr<CefBrowser>, bool fullscreen) override {
        [owner_ handleFullscreen:fullscreen];
    }

    void OnFindResult(CefRefPtr<CefBrowser>, int, int count, const CefRect &, int activeMatchOrdinal, bool) override {
        [owner_ handleFindCount:count active:activeMatchOrdinal];
    }

    // Chromium's menu plus what people expect from Chrome: link and image items on top,
    // Inspect Element at the bottom.
    void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override {
        size_t index = 0;
        if (!params->GetLinkUrl().empty()) {
            model->InsertItemAt(index++, kOpenLinkInNewTab, "Open Link in New Tab");
            model->InsertItemAt(index++, kCopyLink, "Copy Link");
            model->InsertSeparatorAt(index++);
        }
        if (params->GetMediaType() == CM_MEDIATYPE_IMAGE && !params->GetSourceUrl().empty()) {
            model->InsertItemAt(index++, kOpenImageInNewTab, "Open Image in New Tab");
            model->InsertItemAt(index++, kSaveImage, "Save Image");
            model->InsertItemAt(index++, kCopyImageAddress, "Copy Image Address");
            model->InsertSeparatorAt(index++);
        }
        size_t count = model->GetCount();
        if (count > 0 && model->GetTypeAt(count - 1) != MENUITEMTYPE_SEPARATOR) model->AddSeparator();
        model->AddItem(kInspectElement, "Inspect Element");
    }

    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params,
                              int commandID, EventFlags) override {
        switch (commandID) {
        case kOpenLinkInNewTab: [owner_ handlePopup:@(params->GetLinkUrl().ToString().c_str())]; return true;
        case kCopyLink: CopyToPasteboard(params->GetLinkUrl().ToString()); return true;
        case kOpenImageInNewTab: [owner_ handlePopup:@(params->GetSourceUrl().ToString().c_str())]; return true;
        case kSaveImage: browser->GetHost()->StartDownload(params->GetSourceUrl()); return true;
        case kCopyImageAddress: CopyToPasteboard(params->GetSourceUrl().ToString()); return true;
        case kInspectElement: {
            CefWindowInfo windowInfo;
            CefBrowserSettings settings;
            browser->GetHost()->ShowDevTools(windowInfo, new DevToolsClient(), settings,
                                             CefPoint(params->GetXCoord(), params->GetYCoord()));
            return true;
        }
        default: return false;
        }
    }

    void Detach() { owner_ = nil; }

private:
    __weak EMBCEFBrowser *owner_;
    IMPLEMENT_REFCOUNTING(EmbarkClient);
};

// Settings ▸ Privacy ▸ Block third-party cookies, applied to every profile.
bool gBlocksThirdPartyCookies = false;

void ApplyCookiePreference(CefRefPtr<CefRequestContext> context) {
    // 1 blocks third-party cookies, 0 allows them (Chrome's cookie_controls_mode).
    auto value = CefValue::Create();
    value->SetInt(gBlocksThirdPartyCookies ? 1 : 0);
    CefString error;
    if (context->CanSetPreference("profile.cookie_controls_mode")) {
        context->SetPreference("profile.cookie_controls_mode", value, error);
    }
}

// Preferences can only be set once a context has finished starting.
class ContextHandler : public CefRequestContextHandler {
public:
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override { ApplyCookiePreference(context); }

private:
    IMPLEMENT_REFCOUNTING(ContextHandler);
};

std::map<std::string, CefRefPtr<CefRequestContext>> gContexts;

// One request context per profile directory, shared by every tab in that profile.
CefRefPtr<CefRequestContext> ContextForProfile(NSURL *directory) {
    std::string key = directory.path.UTF8String;
    auto found = gContexts.find(key);
    if (found != gContexts.end()) return found->second;
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = key;
    settings.persist_session_cookies = true;
    auto context = CefRequestContext::CreateContext(settings, new ContextHandler());
    gContexts[key] = context;
    return context;
}

std::map<std::string, CefRefPtr<CefRequestContext>> gPrivateContexts;

// An in-memory request context: an empty cache path keeps nothing on disk.
CefRefPtr<CefRequestContext> ContextForPrivateSession(NSString *sessionID) {
    std::string key = sessionID.UTF8String;
    auto found = gPrivateContexts.find(key);
    if (found != gPrivateContexts.end()) return found->second;
    CefRequestContextSettings settings;
    auto context = CefRequestContext::CreateContext(settings, new ContextHandler());
    gPrivateContexts[key] = context;
    return context;
}

/// Calls back on the main thread once cookies are deleted.
class CookiesDeleted : public CefDeleteCookiesCallback {
public:
    explicit CookiesDeleted(void (^completion)(void)) : completion_(completion) {}
    void OnComplete(int) override { dispatch_async(dispatch_get_main_queue(), completion_); }

private:
    void (^completion_)(void);
    IMPLEMENT_REFCOUNTING(CookiesDeleted);
};

}  // namespace

@implementation EMBCEFDownloads

+ (id<EMBCEFDownloadObserver>)observer { return gDownloadObserver; }
+ (void)setObserver:(id<EMBCEFDownloadObserver>)observer { gDownloadObserver = observer; }

+ (void)cancel:(uint32_t)identifier {
    auto found = gDownloadCallbacks.find(identifier);
    if (found != gDownloadCallbacks.end()) found->second->Cancel();
}

@end

@implementation EMBCEFRuntime (Settings)

+ (void)setBlocksThirdPartyCookies:(BOOL)block {
    gBlocksThirdPartyCookies = block;
    for (auto &entry : gContexts) ApplyCookiePreference(entry.second);
    for (auto &entry : gPrivateContexts) ApplyCookiePreference(entry.second);
}

+ (void)deleteCookiesInProfileDirectory:(NSURL *)directory completion:(void (^)(void))completion {
    auto manager = ContextForProfile(directory)->GetCookieManager(nullptr);
    if (!manager || !manager->DeleteCookies(CefString(), CefString(), new CookiesDeleted(completion))) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

+ (void)resetPermission:(EMBSitePermission)permission origin:(NSString *)origin profileDirectory:(NSURL *)directory {
    CefString url = origin.UTF8String;
    ContextForProfile(directory)->SetContentSetting(url, url, ContentType(permission), CEF_CONTENT_SETTING_VALUE_DEFAULT);
}

@end

@implementation EMBCEFBrowser {
    NSView *_view;
    CefRefPtr<CefBrowser> _browser;
    CefRefPtr<EmbarkClient> _client;
    BOOL _canGoBack;
    BOOL _canGoForward;
}

- (instancetype)initWithURL:(NSURL *)url profileDirectory:(NSURL *)profileDirectory {
    return [self initWithURL:url context:ContextForProfile(profileDirectory)];
}

- (instancetype)initWithURL:(NSURL *)url privateSessionID:(NSString *)sessionID {
    return [self initWithURL:url context:ContextForPrivateSession(sessionID)];
}

+ (void)endPrivateSession:(NSString *)sessionID {
    gPrivateContexts.erase(sessionID.UTF8String);
}

- (instancetype)initWithURL:(NSURL *)url context:(CefRefPtr<CefRequestContext>)context {
    if ((self = [super init])) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        _view.autoresizesSubviews = YES;
        _client = new EmbarkClient(self);

        CefWindowInfo windowInfo;
        windowInfo.SetAsChild((__bridge void *)_view, CefRect(0, 0, 800, 600));
        CefBrowserSettings browserSettings;
        CefBrowserHost::CreateBrowser(windowInfo, _client, url.absoluteString.UTF8String, browserSettings,
                                      nullptr, context);
    }
    return self;
}

- (NSView *)view { return _view; }
- (BOOL)canGoBack { return _canGoBack; }
- (BOOL)canGoForward { return _canGoForward; }

- (void)loadURL:(NSURL *)url { if (_browser) _browser->GetMainFrame()->LoadURL(url.absoluteString.UTF8String); }
- (void)goBack { if (_browser) _browser->GoBack(); }
- (void)goForward { if (_browser) _browser->GoForward(); }
- (void)reload { if (_browser) _browser->Reload(); }

- (void)find:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext {
    if (_browser) _browser->GetHost()->Find(text.UTF8String, forward, false, findNext);
}

- (void)stopFinding { if (_browser) _browser->GetHost()->StopFinding(true); }
- (void)exitFullscreen { if (_browser) _browser->GetHost()->ExitFullscreen(true); }

- (BOOL)isLoading { return _browser && _browser->IsLoading(); }
- (void)stopLoading { if (_browser) _browser->StopLoad(); }
- (void)print { if (_browser) _browser->GetHost()->Print(); }

// Chromium zoom levels are powers of 1.2: level 1 is 120%.
- (double)zoomFactor { return _browser ? pow(1.2, _browser->GetHost()->GetZoomLevel()) : 1; }
- (void)setZoomFactor:(double)factor { if (_browser) _browser->GetHost()->SetZoomLevel(log(factor) / log(1.2)); }

- (void)showDevTools {
    if (!_browser) return;
    CefWindowInfo windowInfo;
    CefBrowserSettings settings;
    _browser->GetHost()->ShowDevTools(windowInfo, new DevToolsClient(), settings, CefPoint());
}

- (void)close {
    if (_client) _client->Detach();
    if (_browser) _browser->GetHost()->CloseBrowser(true);
    _browser = nullptr;
    [_view removeFromSuperview];
}

- (void)handleCreated:(CefRefPtr<CefBrowser>)browser {
    _browser = browser;
    if (_tabAudioMuted) _browser->GetHost()->SetAudioMuted(true);
    // CEF adds its own NSView; make it follow our container's size.
    for (NSView *child in _view.subviews) {
        child.frame = _view.bounds;
        child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
}

- (CefRefPtr<CefSSLStatus>)sslStatus {
    if (!_browser) return nullptr;
    auto entry = _browser->GetHost()->GetVisibleNavigationEntry();
    return entry ? entry->GetSSLStatus() : nullptr;
}

- (BOOL)isSecure {
    auto status = [self sslStatus];
    return status && status->IsSecureConnection() && !CefIsCertStatusError(status->GetCertStatus());
}

- (BOOL)hasCertificateError {
    auto status = [self sslStatus];
    return status && CefIsCertStatusError(status->GetCertStatus());
}

- (EMBCEFCertificate *)certificate {
    auto status = [self sslStatus];
    auto certificate = status ? status->GetX509Certificate() : nullptr;
    if (!certificate) return nil;
    EMBCEFCertificate *info = [EMBCEFCertificate new];
    info.subject = @(certificate->GetSubject()->GetDisplayName().ToString().c_str());
    info.issuer = @(certificate->GetIssuer()->GetDisplayName().ToString().c_str());
    info.validFrom = DateFromBaseTime(certificate->GetValidStart());
    info.validUntil = DateFromBaseTime(certificate->GetValidExpiry());
    return info;
}

- (CefString)pageURL {
    return _browser ? _browser->GetMainFrame()->GetURL() : CefString();
}

- (EMBPermissionValue)permission:(EMBSitePermission)permission {
    if (!_browser) return EMBPermissionValueDefault;
    CefString url = [self pageURL];
    return PermissionValue(_browser->GetHost()->GetRequestContext()->GetContentSetting(url, url, ContentType(permission)));
}

- (EMBPermissionValue)defaultPermission:(EMBSitePermission)permission {
    if (!_browser) return EMBPermissionValueDefault;
    return PermissionValue(_browser->GetHost()->GetRequestContext()->GetContentSetting(CefString(), CefString(), ContentType(permission)));
}

- (void)setPermission:(EMBSitePermission)permission value:(EMBPermissionValue)value {
    if (!_browser) return;
    CefString url = [self pageURL];
    _browser->GetHost()->GetRequestContext()->SetContentSetting(url, url, ContentType(permission), ContentValue(value));
    if (permission == EMBSitePermissionSound) [self setAudioMuted:value == EMBPermissionValueBlock];
}

- (void)setAudioMuted:(BOOL)muted {
    if (_browser) _browser->GetHost()->SetAudioMuted(muted || _tabAudioMuted);
}

- (void)setTabAudioMuted:(BOOL)muted {
    _tabAudioMuted = muted;
    if (_browser) _browser->GetHost()->SetAudioMuted(muted || [self permission:EMBSitePermissionSound] == EMBPermissionValueBlock);
}

- (void)countCookies:(void (^)(NSInteger))completion {
    auto manager = _browser ? _browser->GetHost()->GetRequestContext()->GetCookieManager(nullptr) : nullptr;
    if (!manager || !manager->VisitUrlCookies([self pageURL], true, new CookieCounter(completion))) completion(0);
}

- (void)clearSiteData:(void (^)(void))completion {
    if (!_browser) { completion(); return; }
    NSURL *url = [NSURL URLWithString:@([self pageURL].ToString().c_str())];
    if (!url.host) { completion(); return; }
    // Local storage, IndexedDB, cache and the like for this origin.
    auto params = CefDictionaryValue::Create();
    params->SetString("origin", [NSString stringWithFormat:@"%@://%@", url.scheme, url.host].UTF8String);
    params->SetString("storageTypes", "all");
    _browser->GetHost()->ExecuteDevToolsMethod(0, "Storage.clearDataForOrigin", params);
    // Cookies for the whole site, so subdomain logins go too.
    auto manager = _browser->GetHost()->GetRequestContext()->GetCookieManager(nullptr);
    if (!manager || !manager->VisitAllCookies(new CookieDeleter(RegistrableDomain(url.host.UTF8String), completion))) completion();
}

- (void)handlePermissionRequest:(NSArray<NSNumber *> *)permissions origin:(NSString *)origin
                      requestID:(uint64_t)requestID respond:(void (^)(BOOL))respond {
    [self.delegate cefBrowser:self requestsPermissions:permissions origin:origin requestID:requestID respond:respond];
}

- (void)handlePermissionDismissed:(uint64_t)requestID {
    [self.delegate cefBrowser:self dismissedPermissionRequest:requestID];
}

- (void)handleTitle:(NSString *)title { [self.delegate cefBrowser:self didChangeTitle:title]; }
- (void)handleURL:(NSString *)url {
    // Sites whose sound is turned off in page info stay muted.
    [self setAudioMuted:[self permission:EMBSitePermissionSound] == EMBPermissionValueBlock];
    [self.delegate cefBrowser:self didChangeURL:[NSURL URLWithString:url]];
}

- (void)handlePopup:(NSString *)url {
    NSURL *target = [NSURL URLWithString:url];
    if (!target) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate cefBrowser:self requestsNewTab:target]; });
}

- (void)handleLoading:(BOOL)isLoading progress:(double)progress {
    [self.delegate cefBrowser:self didChangeLoading:isLoading progress:progress];
}

- (void)handleFavicon:(NSData *)png {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate cefBrowser:self didChangeFavicon:png]; });
}

- (void)handleCredentialsForHost:(NSString *)host realm:(NSString *)realm isProxy:(BOOL)isProxy
                         respond:(void (^)(NSString *, NSString *))respond {
    [self.delegate cefBrowser:self requestsCredentialsForHost:host realm:realm isProxy:isProxy respond:respond];
}

- (void)handleCertificateErrorForURL:(NSURL *)url description:(NSString *)description respond:(void (^)(BOOL))respond {
    [self.delegate cefBrowser:self certificateErrorForURL:url description:description respond:respond];
}

- (void)handleFindCount:(int)count active:(int)active {
    [self.delegate cefBrowser:self didFindMatches:count active:active];
}

- (void)handleFullscreen:(BOOL)fullscreen { [self.delegate cefBrowser:self didChangeFullscreen:fullscreen]; }

- (void)handleLoginMessage:(NSString *)message {
    [self.delegate cefBrowser:self didPostLoginMessage:message];
}

- (void)handleMediaMessage:(NSString *)message {
    [self.delegate cefBrowser:self didPostMediaMessage:message];
}

- (void)runScript:(NSString *)script {
    if (!_browser) return;
    auto frame = _browser->GetMainFrame();
    if (frame) frame->ExecuteJavaScript(script.UTF8String, frame->GetURL(), 0);
}

- (void)handleRenderProcessTerminatedOutOfMemory:(BOOL)outOfMemory {
    [self.delegate cefBrowser:self renderProcessTerminatedOutOfMemory:outOfMemory];
}

- (void)handleNavigationStateBack:(BOOL)back forward:(BOOL)forward {
    _canGoBack = back;
    _canGoForward = forward;
    [self.delegate cefBrowserDidChangeNavigationState:self];
}

@end
