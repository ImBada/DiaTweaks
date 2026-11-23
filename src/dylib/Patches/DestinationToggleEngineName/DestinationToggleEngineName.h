#import "StdPatch/StdPatch.h"

extern DPPatch DPDestinationToggleEngineName;

NSString *DPEngineNameForWindow(NSWindow *window);
NSString *DPEngineDisplayName(NSString *name);
BOOL DPRelabelEngineText(NSView *root, NSString *name);
BOOL DPRelabelPopover(NSPopover *popover, NSString *name);
BOOL DPRelabelMenu(NSMenu *menu, NSString *name);
BOOL DPApplyMenu(NSMenu *menu, NSView *view);
BOOL DPApplyEngineNameToView(NSView *root, NSWindow *fallbackWindow);
void DPApplyEngineNameToWindows(void);
