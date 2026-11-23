#import "StdPatch/StdPatch.h"

extern DPPatch DPCommandBarHideTab;

BOOL DPHiding(void);

void DPExpectNewTab(NSWindow *window);
void DPStopExpecting(void);
void DPHideTabRow(NSString *tabID, NSWindow *window);
void DPForgetWindow(NSWindow *window);
void DPCleanHideTab(void);
void DPShowTabRow(NSString *tabID, BOOL closing);
BOOL DPHidesTab(NSString *tabID);
BOOL DPHiddenTab(NSString *tabID);
BOOL DPHidingATab(NSWindow *window);
void DPParkTab(NSString *tabID, BOOL parked);
void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window);
BOOL DPParksTab(NSString *tabID);
BOOL DPParkingAny(void);

void DPInstallFrozenLists(void);
void DPFreezeLists(NSWindow *window);
NSString *DPRowName(NSCollectionView *list, NSIndexPath *path);
NSString *DPTabIn(NSString *rowName);
NSArray<NSString *> *DPListedTabs(NSWindow *window);
BOOL DPListsTab(NSView *view, NSString *tabID);
BOOL DPOnlyListedTab(NSString *tabID, NSString *closingID, NSWindow *window);
void DPRelayoutLists(void);
NSRect DPDiaRowFrame(NSCollectionViewLayout *layout, NSIndexPath *path);
void DPInstallParkedRows(void);
BOOL DPIsLeftOutRow(NSCollectionView *list, NSIndexPath *path);
CGFloat DPClosedUp(NSCollectionViewLayout *layout, NSRect frame);
CGFloat DPParkedHeight(NSCollectionViewLayout *layout);
NSCollectionViewLayoutAttributes *DPClosedAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes);
NSString *DPVerifyHiddenRows(void);

void DPInstallHiddenStripTab(void);
void DPHoldStrips(NSWindow *window);
void DPReleaseStrips(void);
NSString *DPStripTabID(NSView *tabView);

BOOL DPSelectionLayoutKnown(void);
extern const uintptr_t DPFirstFill;
BOOL DPStyleSelected(uintptr_t style);
BOOL DPStyleNone(uintptr_t style);
NSView *DPIvarView(NSView *view, const char *name);
uintptr_t *DPSelectionStyle(NSView *background);
NSView *DPTabShapeView(NSView *background);
uint8_t *DPTabShape(NSView *background);
BOOL DPDrawnSelected(NSView *background);
BOOL DPInStrip(NSView *view);
void DPNoteLook(NSView *background);
NSArray *DPSelectedLook(NSView *button);

void DPInstallStandIn(void);
BOOL DPIsNewTabButton(NSView *view);
void DPInstallPress(void);
void DPStandInFor(NSWindow *window, NSString *tabID);
void DPStandInForTab(NSWindow *window, NSString *tabID);
void DPStandInWhileSwitching(NSWindow *window, NSString *tabID, NSString *leaving);
BOOL DPSwitchingTo(NSView *background);
void DPEndSwitch(NSWindow *window);
void DPRefreshStandIns(void);
void DPInstallFrontTab(void);
void DPUnselectFrontTab(NSView *background, BOOL standingIn);
void DPGiveBackSelection(NSView *background);
BOOL DPHoldsSelection(NSView *background);
NSString *DPVerifyStandIn(NSWindow *window, NSString *tabID);
