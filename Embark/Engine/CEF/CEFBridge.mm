#import "CEFBridge.h"

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_library_loader.h"

#include <map>
#include <objc/runtime.h>
#include <string>

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
NSTimer *gPumpTimer = nil;
// Every open browser, so they can all be closed before CefShutdown (which requires it).
std::map<int, CefRefPtr<CefBrowser>> gBrowsers;
void (^gAllBrowsersClosed)(void) = nil;

// Embark keeps AppKit's run loop and drives CEF with an external message pump.
class EmbarkApp : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

    void OnScheduleMessagePumpWork(int64_t delayMs) override {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, MAX(delayMs, 0) * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ CefDoMessageLoopWork(); });
    }

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

    // Safety net in case scheduled work is missed; cheap when idle.
    gPumpTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *) {
        CefDoMessageLoopWork();
    }];
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
    [gPumpTimer invalidate];
    gPumpTimer = nil;
    CefShutdown();
    delete gLibraryLoader;
    gLibraryLoader = nullptr;
}

@end

// MARK: - Browser

@interface EMBCEFBrowser ()
- (void)handleTitle:(NSString *)title;
- (void)handleURL:(NSString *)url;
- (void)handlePopup:(NSString *)url;
- (void)handleNavigationStateBack:(BOOL)back forward:(BOOL)forward;
- (void)handleCreated:(CefRefPtr<CefBrowser>)browser;
@end

namespace {

class EmbarkClient : public CefClient,
                     public CefDisplayHandler,
                     public CefLifeSpanHandler,
                     public CefLoadHandler {
public:
    explicit EmbarkClient(EMBCEFBrowser *owner) : owner_(owner) {}

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }

    void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override {
        [owner_ handleTitle:@(title.ToString().c_str())];
    }

    void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString &url) override {
        if (frame->IsMain()) [owner_ handleURL:@(url.ToString().c_str())];
    }

    void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool, bool canGoBack, bool canGoForward) override {
        [owner_ handleNavigationStateBack:canGoBack forward:canGoForward];
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

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        gBrowsers.erase(browser->GetIdentifier());
        if (gBrowsers.empty() && gAllBrowsersClosed) {
            auto completion = gAllBrowsersClosed;
            gAllBrowsersClosed = nil;
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    }

    // Popups and target=_blank become tabs in the same space instead of new windows.
    bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString &targetURL,
                       const CefString &, WindowOpenDisposition, bool, const CefPopupFeatures &,
                       CefWindowInfo &, CefRefPtr<CefClient> &, CefBrowserSettings &,
                       CefRefPtr<CefDictionaryValue> &, bool *) override {
        [owner_ handlePopup:@(targetURL.ToString().c_str())];
        return true;
    }

    void Detach() { owner_ = nil; }

private:
    __weak EMBCEFBrowser *owner_;
    IMPLEMENT_REFCOUNTING(EmbarkClient);
};

// One request context per profile directory, shared by every tab in that profile.
CefRefPtr<CefRequestContext> ContextForProfile(NSURL *directory) {
    static std::map<std::string, CefRefPtr<CefRequestContext>> contexts;
    std::string key = directory.path.UTF8String;
    auto found = contexts.find(key);
    if (found != contexts.end()) return found->second;
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = key;
    settings.persist_session_cookies = true;
    auto context = CefRequestContext::CreateContext(settings, nullptr);
    contexts[key] = context;
    return context;
}

}  // namespace

@implementation EMBCEFBrowser {
    NSView *_view;
    CefRefPtr<CefBrowser> _browser;
    CefRefPtr<EmbarkClient> _client;
    BOOL _canGoBack;
    BOOL _canGoForward;
}

- (instancetype)initWithURL:(NSURL *)url profileDirectory:(NSURL *)profileDirectory {
    if ((self = [super init])) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        _view.autoresizesSubviews = YES;
        _client = new EmbarkClient(self);

        CefWindowInfo windowInfo;
        windowInfo.SetAsChild((__bridge void *)_view, CefRect(0, 0, 800, 600));
        CefBrowserSettings browserSettings;
        CefBrowserHost::CreateBrowser(windowInfo, _client, url.absoluteString.UTF8String, browserSettings,
                                      nullptr, ContextForProfile(profileDirectory));
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

- (void)close {
    if (_client) _client->Detach();
    if (_browser) _browser->GetHost()->CloseBrowser(true);
    _browser = nullptr;
    [_view removeFromSuperview];
}

- (void)handleCreated:(CefRefPtr<CefBrowser>)browser {
    _browser = browser;
    // CEF adds its own NSView; make it follow our container's size.
    for (NSView *child in _view.subviews) {
        child.frame = _view.bounds;
        child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
}

- (void)handleTitle:(NSString *)title { [self.delegate cefBrowser:self didChangeTitle:title]; }
- (void)handleURL:(NSString *)url { [self.delegate cefBrowser:self didChangeURL:[NSURL URLWithString:url]]; }

- (void)handlePopup:(NSString *)url {
    NSURL *target = [NSURL URLWithString:url];
    if (!target) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate cefBrowser:self requestsNewTab:target]; });
}

- (void)handleNavigationStateBack:(BOOL)back forward:(BOOL)forward {
    _canGoBack = back;
    _canGoForward = forward;
    [self.delegate cefBrowserDidChangeNavigationState:self];
}

@end
