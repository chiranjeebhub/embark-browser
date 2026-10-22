// Objective-C face of the Chromium Embedded Framework, so Swift never touches C++.
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class EMBCEFBrowser;

@protocol EMBCEFBrowserDelegate <NSObject>
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeTitle:(nullable NSString *)title;
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeURL:(nullable NSURL *)url;
- (void)cefBrowser:(EMBCEFBrowser *)browser requestsNewTab:(NSURL *)url;
- (void)cefBrowserDidChangeNavigationState:(EMBCEFBrowser *)browser;
@end

/// Process-wide CEF setup. Call `startWithCacheRoot:` once, before any window appears.
@interface EMBCEFRuntime : NSObject
+ (BOOL)startWithCacheRoot:(NSURL *)cacheRoot;
+ (void)shutdown;
@end

/// One Chromium browser (tab). `profileDirectory` keeps its cookies and logins apart.
@interface EMBCEFBrowser : NSObject
- (instancetype)initWithURL:(NSURL *)url profileDirectory:(NSURL *)profileDirectory;
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<EMBCEFBrowserDelegate> delegate;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
- (void)loadURL:(NSURL *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)close;
@end

/// CEF requires the NSApplication subclass to implement CefAppProtocol.
/// Info.plist must set NSPrincipalClass to EMBApplication when the CEF engine is on.
@interface EMBApplication : NSApplication
@end

NS_ASSUME_NONNULL_END
