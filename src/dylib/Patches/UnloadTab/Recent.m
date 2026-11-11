#import "Patches/UnloadTab/Recent.h"

static NSMapTable<NSWindow *, NSMutableArray<NSString *> *> *DPRecent;  // Each window's tab IDs, the one in front last.

static void DPNoteFront(NSWindow *window) {
    NSString *active = window && DPUnloadTab.on ? DPActiveTabID(window) : nil;
    if (!active) return;
    NSMutableArray *recent = [DPRecent objectForKey:window];
    if (!recent) [DPRecent setObject:(recent = [NSMutableArray array]) forKey:window];
    [recent removeObject:active];
    [recent addObject:active];
    if (recent.count > 20) [recent removeObjectAtIndex:0];
}

// The tab you were on before the one in front, or else one next to it.
id DPTabBefore(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    for (NSString *tabID in [DPRecent objectForKey:window].reverseObjectEnumerator) {
        id tab = [tabID isEqual:active] ? nil : DPScriptTab(window, tabID);
        if (tab) return tab;
    }
    NSArray *tabs = [DPScriptWindow(window) valueForKey:@"appleScriptTabs"];
    NSUInteger i = active ? [[tabs valueForKey:@"tabId"] indexOfObject:active] : NSNotFound;
    if (i == NSNotFound) return nil;
    return i + 1 < tabs.count ? tabs[i + 1] : i > 0 ? tabs[i - 1] : nil;
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    DPNoteFront(self.window);
}

void DPWatchFrontTabs(void) {
    DPRecent = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
}
