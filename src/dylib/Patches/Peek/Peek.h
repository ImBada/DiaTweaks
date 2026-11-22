#import "StdPatch/StdPatch.h"

extern DPPatch DPPeek, DPPeekPinnedLinks;

typedef NS_ENUM(NSInteger, DPPeekExit) { DPPeekClose, DPPeekTab, DPPeekSplit };
typedef NS_ENUM(NSInteger, DPPeekStep) { DPPeekBack, DPPeekForward, DPPeekReload };

// Dia's ArcWebContentsNavigationDisposition, numbered differently from Chromium's.
enum { DPIgnoreAction = 0, DPCurrentTab = 1, DPForegroundTab = 2, DPBackgroundTab = 3, DPNewWindow = 5, DPPopup = 6, DPSplitView = 9 };

@protocol DPPeekPage <NSObject>
- (NSView *)createPaneHostView;
- (void)attachToPaneHostView:(NSView *)host;
- (void)detachFromPaneHostView:(NSView *)host;
@end

@interface DPPeekCard : NSView
@property (nonatomic, strong) NSView *dim, *card, *shade, *clip, *host, *controls, *tabBadge, *toolbar, *toolbarZone;
@property (nonatomic, strong) id<DPPeekPage> page;
@property (nonatomic, weak) id sourceDelegate, source;
@property (nonatomic, copy) NSURL *requestedURL;
@property (nonatomic, copy) NSString *originTabID;
@property (nonatomic, weak) NSWindow *originWindow;
@property (nonatomic, weak) NSView *pane;
@property (nonatomic, strong) id paneObserver, monitor, chatBridge;
@property (nonatomic) NSRect link;
@property (nonatomic) CGFloat grown;
@property (nonatomic) BOOL closing, hadSource;
@property (nonatomic) NSInteger paneMoves;
- (NSRect)cardFrame;
- (void)close:(DPPeekExit)exit;
- (void)handOverTo:(NSView *)destination attach:(void (^)(void))attach;
@end

@interface DPPeekCard (Visibility)
- (void)setOriginVisible:(BOOL)visible;
@end

@interface DPPeekCard (Motion)
- (void)animateIn;
- (void)animateOut:(void (^)(void))completion;
- (void)animateExpand:(void (^)(void))completion;
- (void)stopMotion;
@end

@interface DPPeekCard (Handoff)
- (void)finish:(DPPeekExit)exit;
@end

// Active visible (non-closing, non-hidden) Peek card in window, or nil.
DPPeekCard *DPPeekCardIn(NSWindow *window);
// Active visible Peek's hosted page in window, or nil.
id DPPeekPageIn(NSWindow *window);
// All tracked Peek cards in window (or all windows when window is nil), including hidden and closing cards.
NSArray<DPPeekCard *> *DPPeekAllCards(NSWindow *window);
// Non-closing hidden background Peek cards in window (or all windows when window is nil).
NSArray<DPPeekCard *> *DPPeekHiddenCards(NSWindow *window);
// Tracked Peek card whose hosted page is page (visible or hidden), or nil.
DPPeekCard *DPPeekCardForPage(id page);
// Tracked non-closing Peek card pinned to originTabID (or source) in window, or nil.
DPPeekCard *DPPeekCardForOrigin(NSWindow *window, NSString *originTabID, id source);
BOOL DPPeekHasCards(void);
DPPeekCard *DPPeekShowCard(NSWindow *window, id<DPPeekPage> page, NSView *warmHost, NSRect screenLink);
NSView *DPPeekWarmHost(NSWindow *window, id<DPPeekPage> page);
NSView *DPPeekPane(NSWindow *window, NSRect area);
NSView *DPPeekHolder(NSWindow *window, NSView *pane);
void DPPeekWatchPane(DPPeekCard *peek, NSView *pane);
id DPPeekWatchKeys(DPPeekCard *card);
NSEvent *DPPeekHandleKeyEvent(DPPeekCard *peek, NSEvent *event);

NSView *DPPeekControls(id target, SEL action);
void DPPeekResetControlHints(NSView *controls);
extern const CGFloat DPPeekToolbarHeight;
NSView *DPPeekToolbarFor(id page);
void DPPeekAddToolbar(DPPeekCard *peek);
CGFloat DPPeekToolbarInset(DPPeekCard *peek);
void DPPeekPlaceToolbar(DPPeekCard *peek);
void DPPeekNavigate(id page, DPPeekStep step);
NSView *DPPeekToolbarAddress(NSView *toolbar);
NSView *DPPeekAddressFor(id page);
NSView *DPPeekGlowFor(id page);
void DPPeekRefreshAddress(NSView *address);
void DPPeekEditAddress(NSView *address);
BOOL DPPeekEditingAddress(NSView *address);
void DPPeekEditToolbarAddress(DPPeekCard *peek);
NSURL *DPPeekSearchURL(id page, NSString *text);
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event);
BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item);
BOOL DPPeekZoomShortcut(DPPeekCard *peek, NSEvent *event);
BOOL DPPeekFindShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods);
BOOL DPPeekHideFind(DPPeekCard *peek);
void DPPeekInstallZoom(void);
void DPPeekInstallCursor(void);
NSString *DPPeekZoomProblem(void);
void DPPeekLayoutHints(NSView *controls, CGFloat availableRight);
CATransform3D DPPeekScaled(NSView *view, CGFloat scale);
CASpringAnimation *DPPeekSpring(NSString *keyPath, CFTimeInterval response, CGFloat dampingRatio);

BOOL DPPeekInPinnedRow(NSWindow *window, id page);
void DPPeekShowTabBadge(DPPeekCard *peek, id source);
void DPPeekHideTabBadge(DPPeekCard *peek);
void DPPeekRefreshTabBadge(DPPeekCard *peek);
BOOL DPPeekTabBadgeSelected(DPPeekCard *peek, BOOL *known);

void DPPeekInstallSelection(void);
void DPPeekSyncTabs(NSWindow *window);
void DPPeekCloseForSource(id source);
void DPPeekUpdateSyncTimer(void);

double DPPeekDarkness(void);
double DPPeekResponse(void);
BOOL DPPeekGenie(void);
BOOL DPPeekShowsToolbar(void);
NSArray<NSView *> *DPPeekSettingsRows(void);

extern BOOL DPPeekGiving;
extern BOOL DPPeekFindingLink;

void DPPeekInstallChat(void);
void DPPeekInstallChatContext(void);
void DPPeekChatAttach(DPPeekCard *peek);
void DPPeekChatDetach(DPPeekCard *peek);
void DPPeekChatDetachQuiet(DPPeekCard *peek);
void DPPeekChatDetachBridge(id bridge);
void DPPeekChatVisibilityDidChange(DPPeekCard *peek);
NSView *DPPeekChatHolder(NSWindow *window, NSView *pane);
NSArray *DPPeekWatchPaneAncestors(DPPeekCard *peek, NSView *pane, NSView *holder);
void DPPeekUnwatchPane(id observer);
BOOL DPPeekAllowsPaneClick(DPPeekCard *peek, NSPoint pointInSuperview);
NSRect DPPeekControlsFrame(DPPeekCard *peek, NSRect controlsFrame);
BOOL DPPeekResponderInChat(id responder);
BOOL DPPeekChatShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods);

void DPPeekInstallPages(void);
void DPPeekPrepareHandoff(DPPeekCard *peek, void (^complete)(void));
void DPPeekCompleteHandoff(DPPeekCard *peek, NSView *destination);
void DPPeekHandoffSelectionChanged(NSWindow *window, NSString *active);
void DPPeekHandoffSync(void);
void DPPeekCancelHandoffs(void);
BOOL DPPeekHandoffActive(void);
BOOL DPPeekCanOpen(id source);
BOOL DPPeekShows(id page);
void DPPeekLoad(id page, NSURL *url);
void DPPeekOpen(NSWindow *window, NSString *originTabID, NSURL *url, NSPoint origin, id delegate, id source);
void DPPeekWarm(NSWindow *window, id source, NSURL *url);
void DPPeekCool(void);
void DPPeekCoolIn(NSWindow *window);
void DPPeekCloseAll(void);
void DPPeekHideDragZone(void);
void DPPeekOpenDragged(NSURL *url, NSPoint origin);
BOOL DPPeekIsWeb(NSURL *url);
BOOL DPPeekOverLink(id page, NSURL *url);
NSString *DPPeekLinkKey(NSString *address);
