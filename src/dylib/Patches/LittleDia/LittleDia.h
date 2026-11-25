#import "StdPatch/StdPatch.h"

#define DPDiaOpenURLEvents "_TtC13OpenURLClient19OpenURLEventManager"
#define DPDiaPopupWindow   "_TtC5Popup19PlatformPopupWindow"
#define DPDiaPopupBar      "_TtC5Popup22PopupNavigationBarView"
#define DPDiaPopupTitle    "_TtC13NavigationBar21AssistantBarTitleView"

extern DPPatch DPLittleDia, DPLittleDiaTabLinks, DPLittleDiaFollowRules, DPLittleDiaRemember, DPLittleDiaLauncher;

NSString *DPLittleDiaLinkKey(NSString *address);

void DPInstallLittleDiaExtension(void);
BOOL DPWriteLittleDiaExtension(BOOL on);
NSString *DPLittleDiaExtensionProblem(void);
BOOL DPSendToLittleDia(NSDictionary *request);
BOOL DPLittleDiaStarting(void);
BOOL DPLittleDiaReady(void);

NSSize DPLittleDiaSize(void);
NSRect DPLittleDiaSavedFrame(void);
void DPSaveLittleDiaFrame(NSRect frame);
NSArray<NSView *> *DPLittleDiaRows(void);
void DPSyncLittleDiaEscape(void);

void DPInstallLittleDiaRoute(void);
void DPOpenLinkInLittleDia(NSURL *url);
#define DPTabLinkWidth 0.8
#define DPTabLinkEdge 12
void DPOpenTabLinkInLittleDia(NSURL *url, NSWindow *source);
void DPOpenBlankLittleDia(void);

void DPInstallLittleDiaLinkMenu(void);
NSString *DPLittleDiaLinkMenuProblem(void);

void DPInstallLittleDiaNewWindow(void);
void DPRefreshLittleDiaNewWindow(void);
NSString *DPLittleDiaNewWindowProblem(void);

void DPShowLittleDiaLauncher(void);
void DPToggleLittleDiaLauncher(void);
void DPHideLittleDiaLauncher(void);
BOOL DPLittleDiaLauncherVisible(void);
NSURL *DPLittleDiaSearchURL(NSString *text);

#define DPLittleDiaWait 3
void DPExpectLittleDiaWindow(NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window));
BOOL DPIsLittleDiaWindow(NSWindow *window);
id DPLittleDiaPage(NSWindow *window);
void DPInstallLittleDiaWindows(void);
void DPRefreshLittleDiaWindows(void);
void DPPromoteLittleDiaWindow(NSWindow *window);

void DPInstallLittleDiaOver(void);
void DPSyncLittleDiaOver(void);
void DPPutLittleDiaOver(NSWindow *little, NSWindow *window);
BOOL DPLittleDiaIsOver(NSWindow *window);
void DPUncoverAllLittleDia(void);

void DPInstallLittleDiaStack(void);
NSDictionary *DPNoteStackForLink(void);
void DPRestoreStack(NSWindow *little, NSDictionary *noted);
void DPRestoreLittleDiaStack(void);
NSArray<NSDictionary *> *DPWindowStack(void);
void DPReturnToSource(pid_t pid, NSWindow *little, NSArray<NSDictionary *> *stack);
void DPBringBackPutAway(NSWindow *little);
NSArray<NSWindow *> *DPPutAwayWindows(void);
void DPLinkArrived(void);
BOOL DPHideAgain(void);

void DPInstallLittleDiaBar(void);
NSButton *DPMakeBarButton(NSString *symbol, NSString *label, NSString *key, void (^action)(void));
NSView *DPMakeDivider(void);
void DPMatchPage(NSView *row, id page);
void DPRelayoutLittleDiaBars(void);

NSView *DPMakeAddressView(NSView *title);
void DPRefreshAddressView(NSView *view);
void DPEditLittleDiaAddress(NSWindow *window);
void DPShowLittleDiaNotice(NSWindow *window, NSString *message);

void DPInstallLittleDiaShortcuts(void);
NSString *DPLittleDiaShortcutsProblem(void);

NSString *DPLittleDiaURL(NSWindow *window);
NSDictionary *DPLittleDiaTab(NSWindow *window, NSString *action);
void DPLittleDiaGo(NSWindow *window, SEL action);
void DPLittleDiaNavigate(NSWindow *window, NSString *typed);

NSArray<NSString *> *DPLittleDiaProfiles(void);
NSImage *DPLittleDiaProfileImage(NSString *name);
NSString *DPOpenInLabel(NSString *profile, NSUInteger profiles);
NSString *DPLittleDiaProfileName(NSWindow *window);
void DPOpenInProfile(NSString *url, NSUInteger index, void (^done)(BOOL opened));
