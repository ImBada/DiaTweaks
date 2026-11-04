#import "SidebarAddressBar.h"
#import "Patches/HideToolbar/HideToolbar.h"

void DPSidebarRestoreToolbar(NSView *pane);
void DPSidebarApplyToolbar(NSView *pane);
void DPSidebarStopToolbarHover(DPToolbarHover *hover);
void DPSidebarInstallToolbarHover(void);
void DPSidebarInstallToolbarVerification(void);
NSString *DPSidebarVerifyToolbar(void);
NSRect DPSidebarToolbarBase(NSView *view);
void DPSidebarCheckToolbarState(void);
