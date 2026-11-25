#import "StdPatch/StdPatch.h"

extern NSHashTable<NSView *> *DPHideHosts;
extern NSHashTable<NSView *> *DPSuppressed;
extern const char *const DPHideHostClasses[];

BOOL DPAnyHidesOn(void);
DPPatch *DPHider(NSView *view);
// Until DPShareLabel(nil), DPHasLabel reads view's label once for every rule that asks; AppKit derives it slowly when none was set.
void DPShareLabel(NSView *view);
void DPEnforceHides(NSView *root);
void DPApplyHides(DPPatch *patch);
NSString *DPVerifyHides(DPPatch *patch);
void DPInstallHides(void);
void DPInstallHideHosts(void);
// For a hide that Dia lays out away from every host: its own layout then enforces the hides.
void DPHostHides(const char *className);
