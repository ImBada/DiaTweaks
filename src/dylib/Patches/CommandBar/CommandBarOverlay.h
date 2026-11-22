#import "StdPatch/StdPatch.h"

extern DPPatch DPCommandBar, DPCommandBarKeepText;

@interface DPCommandBarOverlay : NSView
@property(weak) NSView *page, *panel;
@property(weak) NSWindow *host;
@property(strong) NSView *shade, *windowBlur;
@property(strong) id openedTab, returnTab, keyMonitor;
@property(strong) NSArray<NSView *> *shownShadows;
@property(strong) NSTimer *watch;
@property(copy) NSString *startURL;
@property CGFloat collapsedHeight, collapsedWidth;
@property CFTimeInterval sizedAt, listlessSince;
@property BOOL picked, overBlank, passingThrough;
- (NSView *)viewUnder:(NSPoint)point;
@end

extern char DPOverlayKey;

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
NSUserDefaults *DPSettings(void);
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
void DPNoteSpare(NSString *tabID, BOOL parked);
BOOL DPAdoptSpare(NSWindow *window, NSView *page);
void DPWantSpare(void);
void DPNotMakingSpare(void);
