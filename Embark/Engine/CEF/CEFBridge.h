// Objective-C face of the Chromium Embedded Framework, so Swift never touches C++.
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class EMBCEFBrowser;

/// Per-site permissions shown in page info. Values match `SitePermission` in Swift.
typedef NS_ENUM(NSInteger, EMBSitePermission) {
    EMBSitePermissionCamera,
    EMBSitePermissionMicrophone,
    EMBSitePermissionNotifications,
    EMBSitePermissionSound,
    EMBSitePermissionAutoPictureInPicture,
};

/// A permission's setting for a site. Values match `PermissionValue` in Swift.
typedef NS_ENUM(NSInteger, EMBPermissionValue) {
    EMBPermissionValueDefault,
    EMBPermissionValueAllow,
    EMBPermissionValueBlock,
    EMBPermissionValueAsk,
};

/// The page's TLS certificate, for page info.
@interface EMBCEFCertificate : NSObject
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSDate *validFrom;
@property (nonatomic, copy) NSDate *validUntil;
@end

@protocol EMBCEFBrowserDelegate <NSObject>
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeTitle:(nullable NSString *)title;
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeURL:(nullable NSURL *)url NS_SWIFT_NAME(cefBrowser(_:didChangeURL:));
- (void)cefBrowser:(EMBCEFBrowser *)browser requestsNewTab:(NSURL *)url;
- (void)cefBrowserDidChangeNavigationState:(EMBCEFBrowser *)browser;
/// The page asks for permissions (`EMBSitePermission` values). Call `respond` once.
- (void)cefBrowser:(EMBCEFBrowser *)browser
    requestsPermissions:(NSArray<NSNumber *> *)permissions
                 origin:(NSString *)origin
              requestID:(uint64_t)requestID
                respond:(void (^)(BOOL allow))respond NS_SWIFT_NAME(cefBrowser(_:requestsPermissions:origin:requestID:respond:));
/// Chromium withdrew a request, e.g. after navigating away.
- (void)cefBrowser:(EMBCEFBrowser *)browser dismissedPermissionRequest:(uint64_t)requestID;
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

/// The visible page came over a secure connection with a valid certificate.
@property (nonatomic, readonly) BOOL isSecure;
@property (nonatomic, readonly) BOOL hasCertificateError;
@property (nonatomic, readonly, nullable) EMBCEFCertificate *certificate;
/// Permissions for the current page's site, kept by its profile.
- (EMBPermissionValue)permission:(EMBSitePermission)permission;
/// What the profile uses for sites without their own setting.
- (EMBPermissionValue)defaultPermission:(EMBSitePermission)permission;
- (void)setPermission:(EMBSitePermission)permission value:(EMBPermissionValue)value;
- (void)setAudioMuted:(BOOL)muted;
/// Cookies sent to the current page.
- (void)countCookies:(void (^)(NSInteger count))completion;
/// Deletes the site's cookies (its whole registrable domain) and the origin's storage.
- (void)clearSiteData:(void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
