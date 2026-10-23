// Objective-C face of the Chromium Embedded Framework, so Swift never touches C++.
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class EMBCEFBrowser;

@protocol EMBCEFBrowserDelegate <NSObject>
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeTitle:(nullable NSString *)title;
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeURL:(nullable NSURL *)url NS_SWIFT_NAME(cefBrowser(_:didChangeURL:));
- (void)cefBrowser:(EMBCEFBrowser *)browser requestsNewTab:(NSURL *)url;
- (void)cefBrowserDidChangeNavigationState:(EMBCEFBrowser *)browser;
@end

/// Process-wide CEF setup. Call `startWithCacheRoot:` once, before any window appears.
@interface EMBCEFRuntime : NSObject
+ (BOOL)startWithCacheRoot:(NSURL *)cacheRoot;
@property (class, nonatomic, readonly) BOOL hasOpenBrowsers;
/// Closes every browser and calls `completion` once they are gone. Call before `shutdown`.
+ (void)closeAllBrowsers:(void (^)(void))completion;
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

NS_ASSUME_NONNULL_END
