#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"

extern DPPatch DPUnloadTab;

// Which tabs each window had in front, so unloading the one in front can go back to the one before it.
void DPWatchFrontTabs(void);
id DPTabBefore(NSWindow *window);
