#import "StdPatch/StdPatch.h"

extern DPPatch DPCommandBar, DPCommandBarKeepText;

@interface DPCommandBarOverlay : NSView
@property(weak) NSView *page, *panel;
@property(weak) NSWindow *host;
@property(strong) NSView *shade, *windowBlur;
@property(strong) id openedTab, returnTab, keyMonitor;
@property(strong) NSArray *textWatch;
@property(strong) NSArray<NSView *> *shownShadows;
@property(strong) NSTimer *watch;
@property(copy) NSString *startURL;
@property CGFloat collapsedHeight, collapsedWidth, extraHeight;
@property CFTimeInterval sizedAt, listlessSince;
@property BOOL picked, overBlank, passingThrough;
- (NSView *)viewUnder:(NSPoint)point;
@end

extern char DPOverlayKey;

static inline BOOL DPOverPinnedHeader(NSView *tabList, id gesture) {
    static Class headerCls;
    if (!headerCls) headerCls = NSClassFromString(@"DPPinnedHeader");
    if (!headerCls || ![gesture respondsToSelector:@selector(locationInView:)]) return NO;
    NSView *header = DPFindView(tabList, ^BOOL(NSView *view) { return [view isKindOfClass:headerCls]; });
    if (!header || header.isHiddenOrHasHiddenAncestor || !header.superview) return NO;
    return NSPointInRect([gesture locationInView:header.superview], header.frame);
}

static inline void DPStopWatchingText(DPCommandBarOverlay *overlay) {
    for (id observer in overlay.textWatch) [NSNotificationCenter.defaultCenter removeObserver:observer];
    overlay.textWatch = nil;
}

static inline void DPStopWatching(DPCommandBarOverlay *overlay) {
    [overlay.watch invalidate];
    overlay.watch = nil;
    if (overlay.keyMonitor) [NSEvent removeMonitor:overlay.keyMonitor];
    overlay.keyMonitor = nil;
    DPStopWatchingText(overlay);
}

static inline void DPRemoveShade(DPCommandBarOverlay *overlay) {
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
}

static inline NSView *DPVisiblePeek(NSWindow *window) {
    static Class card;
    if (!card) card = NSClassFromString(@"DPPeekCard");
    return card ? DPFindView(window.contentView, ^BOOL(NSView *view) { return [view isKindOfClass:card] && !view.isHiddenOrHasHiddenAncestor; }) : nil;
}

NSTextView *DPBarText(DPCommandBarOverlay *overlay);
void DPFocusBar(DPCommandBarOverlay *overlay);
void DPShowShade(DPCommandBarOverlay *overlay);
id DPDismiss(DPCommandBarOverlay *overlay, BOOL closing);
void DPCancelCommandBar(DPCommandBarOverlay *overlay);
id DPWatchKeys(DPCommandBarOverlay *overlay);
void DPWatch(DPCommandBarOverlay *overlay);
NSMutableSet<NSString *> *DPSplits(NSWindow *window);
NSMutableSet<NSString *> *DPBlanks(NSWindow *window);
NSView *DPBlankPage(NSWindow *window);
void DPMakeBlank(NSView *page, NSString *tab, NSString *closing);
NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title);
void DPShowHiddenBars(void);
BOOL DPHasStrip(NSWindow *window);

BOOL DPInTabLayout(NSView *view);
NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event);
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay);

void DPHandOver(DPCommandBarOverlay *overlay);
void DPFinishHandOver(NSWindow *window);
DPCommandBarOverlay *DPTakeHandOver(NSWindow *window);
void DPClearCatchUp(NSWindow *window);
NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab);
BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab);
void DPDiaCaughtUp(NSWindow *window);

BOOL DPSparesOn(void);
BOOL DPParkSpare(DPCommandBarOverlay *overlay);
void DPParkIfSpare(DPCommandBarOverlay *overlay);
BOOL DPShowSpare(NSWindow *window);
void DPDropSpare(NSWindow *window);
void DPForgetSpare(NSWindow *window);
void DPDropUnwantedSpares(void);
void DPUpdateSpareTimer(void);
DPCommandBarOverlay *DPSpareIn(NSWindow *window);
void DPCloseLeftSpares(NSArray<NSString *> *tabIDs, BOOL last);
void DPCloseLeftOpenTabs(NSArray<NSString *> *tabIDs, BOOL last);
void DPCloseLeftBarTabs(void);
void DPNoteSpare(NSString *tabID, BOOL parked);
void DPNoteOpenTab(NSString *tabID, BOOL open);
BOOL DPAdoptSpare(NSWindow *window, NSView *page);
void DPWantSpare(void);
void DPNotMakingSpare(void);
