#import "StdPatch/StdPatch.h"

extern DPPatch DPUnloadTab;

void DPInstallUnloadPages(void);
void DPRecordVisiblePanePages(void);
id DPPageForPane(NSWindow *window, NSString *contentID);
id DPPageByURL(NSString *tabID, NSString *contentID, NSURL *url);
NSURL *DPScriptTabURL(NSWindow *window, NSString *tabID);
NSCountedSet<NSURL *> *DPScriptTabURLCounts(void);
BOOL DPPageIsDiscarded(id page);
BOOL DPPageIsVisible(id page);
BOOL DPPageIsTracked(id page);
void DPUnloadPage(id page, id before);
