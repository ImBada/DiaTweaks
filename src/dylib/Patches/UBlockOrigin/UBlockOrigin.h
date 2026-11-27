#import "StdPatch/StdPatch.h"

extern DPPatch DPUBlockOrigin;

NSString *DPUBlockFolder(void);  // the unpacked extension Chromium loads
NSString *DPUBlockStaged(void);  // a newer one, moved into DPUBlockFolder while Chromium isn't using it
NSString *DPUBlockVersion(NSString *folder);  // nil unless the folder holds a Manifest V2 extension

// Downloads the latest release into DPUBlockStaged unless it's already there or in DPUBlockFolder. Calls back on the
// main queue with nil, or why it failed.
void DPFetchUBlock(void (^done)(NSString *problem));

// Finds where Chromium turns off Manifest V2 extensions and unpacked ones outside developer mode; NO if they aren't
// where they were.
BOOL DPFindExtensionChecks(void);
// Lets both run. Only before Chromium starts: its extension system reads these as it loads.
BOOL DPLiftExtensionChecks(void);
