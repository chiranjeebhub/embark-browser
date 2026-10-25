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
/// Matches for the current find; `active` counts from 1, 0 when none is selected.
- (void)cefBrowser:(EMBCEFBrowser *)browser didFindMatches:(NSInteger)count active:(NSInteger)active NS_SWIFT_NAME(cefBrowser(_:didFindMatches:active:));
/// The page started or stopped loading; `progress` runs from 0 to 1.
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeLoading:(BOOL)isLoading progress:(double)progress NS_SWIFT_NAME(cefBrowser(_:didChangeLoading:progress:));
/// The page's icon changed; `png` is nil when it has none.
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeFavicon:(nullable NSData *)png NS_SWIFT_NAME(cefBrowser(_:didChangeFavicon:));
/// A site asks for a user name and password (HTTP authentication). Call `respond` once, with
/// nil to cancel.
- (void)cefBrowser:(EMBCEFBrowser *)browser
    requestsCredentialsForHost:(NSString *)host
                         realm:(nullable NSString *)realm
                       isProxy:(BOOL)isProxy
                       respond:(void (^)(NSString *_Nullable user, NSString *_Nullable password))respond
    NS_SWIFT_NAME(cefBrowser(_:requestsCredentialsFor:realm:isProxy:respond:));
/// The site's certificate isn't trusted. Call `respond` once: YES visits it anyway.
- (void)cefBrowser:(EMBCEFBrowser *)browser
    certificateErrorForURL:(NSURL *)url
               description:(NSString *)description
                   respond:(void (^)(BOOL proceed))respond
    NS_SWIFT_NAME(cefBrowser(_:certificateErrorFor:description:respond:));
/// A video or other element went full screen inside the page, or came out of it.
- (void)cefBrowser:(EMBCEFBrowser *)browser didChangeFullscreen:(BOOL)fullscreen NS_SWIFT_NAME(cefBrowser(_:didChangeFullscreen:));
@end

/// Process-wide CEF setup. Call `startWithCacheRoot:` once, before any window appears.
@interface EMBCEFRuntime : NSObject
+ (BOOL)startWithCacheRoot:(NSURL *)cacheRoot;
@property (class, nonatomic, readonly) BOOL hasOpenBrowsers;
/// Closes every browser and calls `completion` once they are gone. Call before `shutdown`.
+ (void)closeAllBrowsers:(void (^)(void))completion;
+ (void)shutdown;
@end

typedef NS_ENUM(NSInteger, EMBDownloadState) {
    EMBDownloadStateInProgress,
    EMBDownloadStateComplete,
    EMBDownloadStateCanceled,
    EMBDownloadStateFailed,
};

/// A snapshot of one download, sent on every change.
@interface EMBCEFDownload : NSObject
@property (nonatomic) uint32_t identifier;
@property (nonatomic, copy, nullable) NSURL *url;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy, nullable) NSURL *fileURL;
@property (nonatomic) int64_t receivedBytes;
/// -1 while the size is unknown.
@property (nonatomic) int64_t totalBytes;
@property (nonatomic) int64_t bytesPerSecond;
@property (nonatomic) EMBDownloadState state;
@end

@protocol EMBCEFDownloadObserver <NSObject>
/// Where to save a new download. Return nil to cancel it.
- (nullable NSURL *)cefDownloadDestinationForSuggestedName:(NSString *)name NS_SWIFT_NAME(cefDownloadDestination(suggestedName:));
- (void)cefDownloadDidUpdate:(EMBCEFDownload *)download;
@end

/// Downloads from every tab and profile go to one observer.
@interface EMBCEFDownloads : NSObject
@property (class, nonatomic, weak, nullable) id<EMBCEFDownloadObserver> observer;
+ (void)cancel:(uint32_t)identifier;
@end

/// One Chromium browser (tab). `profileDirectory` keeps its cookies and logins apart.
@interface EMBCEFBrowser : NSObject
- (instancetype)initWithURL:(NSURL *)url profileDirectory:(NSURL *)profileDirectory;
/// A tab of a private window: cookies and storage stay in memory, shared by the tabs with
/// the same `sessionID`, and are gone after `endPrivateSession:`.
- (instancetype)initWithURL:(NSURL *)url privateSessionID:(NSString *)sessionID;
+ (void)endPrivateSession:(NSString *)sessionID;
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<EMBCEFBrowserDelegate> delegate;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
- (void)loadURL:(NSURL *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)close;

/// Highlights matches of `text`. `findNext` moves to the next match of the same text.
- (void)find:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFinding;
/// Takes a full-screen element back into the page.
- (void)exitFullscreen;

@property (nonatomic, readonly) BOOL isLoading;
- (void)stopLoading;
/// 1 is 100%. Chromium keeps it for the page until it navigates to another site.
@property (nonatomic) double zoomFactor;
- (void)print;
- (void)showDevTools;

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
