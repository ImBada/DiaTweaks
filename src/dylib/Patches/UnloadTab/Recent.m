#import "Patches/UnloadTab/Recent.h"
#import "Patches/UnloadTab/Pages.h"

static NSMapTable<NSWindow *, NSMutableArray<NSString *> *> *DPRecent;

id DPTabBefore(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    id rawTabs = DPValueForKey(DPScriptWindow(window), @"appleScriptTabs");
    NSArray *tabs = [rawTabs isKindOfClass:NSArray.class] ? rawTabs : nil;
    if (!tabs.count) return nil;
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) [ids addObject:DPTabID(tab) ?: NSNull.null];
    for (NSString *tabID in [DPRecent objectForKey:window].reverseObjectEnumerator) {
        NSUInteger i = [tabID isEqual:active] ? NSNotFound : [ids indexOfObject:tabID];
        if (i != NSNotFound) return tabs[i];
    }
    NSUInteger i = active ? [ids indexOfObject:active] : NSNotFound;
    if (i == NSNotFound) return tabs.firstObject;
    if (i + 1 < tabs.count) return tabs[i + 1];
    return i > 0 ? tabs[i - 1] : nil;
}

void DPForgetFrontTab(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    if (active) [[DPRecent objectForKey:window] removeObject:active];
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    if (!DPUnloadTab.on) return;
    NSWindow *window = self.window;
    if (!window) return;
    DPRecordVisiblePanePages();
    NSString *active = DPActiveTabID(window);
    if (!active) return;
    NSMutableArray *recent = [DPRecent objectForKey:window];
    if (!recent) [DPRecent setObject:(recent = [NSMutableArray array]) forKey:window];
    [recent removeObject:active];
    [recent addObject:active];
    if (recent.count > 20) [recent removeObjectAtIndex:0];
}

void DPWatchFrontTabs(void) {
    DPRecent = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
}
