#import "StdPatch/StdPatch.h"

@class DPSidebarAddressRow;

extern DPPatch DPSidebarAddressBar;
extern DPPatch DPSidebarComfortableSpacing;
void DPSidebarApplySpacing(void);
void DPSidebarUpdateHover(NSView *row, BOOL animated);
BOOL DPSidebarRowIsHovered(NSView *row);
void DPSidebarRefreshNativeControls(DPSidebarAddressRow *row);
void DPSidebarRestoreNativeControls(NSView *row);
void DPSidebarLayoutNativeControls(NSView *row);

@interface DPSidebarAddressRow : NSView
@property(copy) NSString *URLString;
- (void)refresh;
- (CGFloat)preferredHeight;
- (BOOL)isEditingAddress;
- (void)setNativeEditorVisible:(BOOL)visible;
- (void)layoutAddressBefore:(CGFloat)edge;
- (void)updateActionHover;
- (BOOL)acceptsAddressMenuAt:(NSPoint)point;
- (void)copyLink:(id)sender;
- (void)showCopyFeedback;
@end

@interface DPSidebarAddressRow (InlineEditor)
- (void)openEditor:(id)sender;
@end
@interface DPSidebarAddressRow (SuggestionSession)
- (void)finishStartingSuggestionSession;
- (void)attachSuggestionSession:(NSView *)panel editor:(NSTextView *)editor;
@end

NSString *DPSidebarURL(NSWindow *window);
NSString *DPSidebarDomain(NSString *URLString);
BOOL DPSidebarOpenEditor(NSView *anchor);
BOOL DPSidebarOpenEditorWithQuery(NSView *anchor, NSString *query);
void DPSidebarRequestPopover(NSView *anchor);
void DPSidebarRequestPopoverWithQuery(NSView *anchor, NSString *query);
void DPSidebarInstallPopover(void);
void DPSidebarInstallLayout(void);
void DPSidebarApplyLayout(void);
void DPSidebarRefreshLayout(void);
BOOL DPSidebarAddressRowAvailable(NSWindow *window);
BOOL DPSidebarUsesVerticalTabs(NSView *root);
NSString *DPSidebarVerifyLayout(DPPatch *patch);

void DPSidebarInstallContextTracking(void);

NSView *DPSidebarEditorAnchor(NSView *view);

BOOL DPSidebarNavigate(NSWindow *window, NSString *address);


BOOL DPSidebarOpenDefaultEditor(NSView *anchor);
BOOL DPSidebarSuggestionsCoverView(NSView *view);

void DPSidebarInstallInlineFocus(void);

void DPSidebarCancelPopoverRequest(NSView *anchor);

NSString *DPSidebarTabIdentifier(NSWindow *window);

extern DPPatch DPSidebarHideTopToolbar;
BOOL DPSidebarReplacesToolbar(NSView *pane);
void DPSidebarInstallToolbar(void);
void DPSidebarRefreshToolbar(void);
void DPSidebarLayoutHeader(NSView *header);
