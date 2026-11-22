#import "LittleDia.h"
#import "Patches/HideToolbar/HideToolbar.h"

static NSMapTable<NSWindow *, NSWindow *> *gOver;

static NSArray<NSView *> *DPToolbars(NSWindow *window) {
    NSMutableArray<NSView *> *bars = [NSMutableArray array];
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        NSView *bar = pane.window == window ? DPSubview(pane, DPDiaToolbar) : nil;
        if (!bar) continue;
        [bars addObject:bar];
        NSView *bookmarks = DPBookmarksUnder(pane, bar);
        if (bookmarks) [bars addObject:bookmarks];
    }
    return bars;
}

static void DPFadeToolbars(NSWindow *window, BOOL hidden) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        for (NSView *bar in DPToolbars(window)) bar.animator.alphaValue = hidden ? 0 : 1;
    } completionHandler:^{
        if (hidden || !DPHideToolbar.on) return;
        for (NSView *pane in DPFindViews(DPDiaContentPane))
            if (pane.window == window) DPApplyToolbar(pane);
    }];
}

BOOL DPLittleDiaIsOver(NSWindow *window) {
    if (!DPLittleDia.on || !window || !gOver.count) return NO;
    NSWindow *little = [gOver objectForKey:window];
    return little.visible && !little.miniaturized;
}

static void DPUncover(NSWindow *little) {
    for (NSWindow *window in gOver.keyEnumerator.allObjects)
        if ([gOver objectForKey:window] == little) {
            [gOver removeObjectForKey:window];
            DPFadeToolbars(window, NO);
        }
}

void DPUncoverAllLittleDia(void) {
    for (NSWindow *window in gOver.keyEnumerator.allObjects) {
        [gOver removeObjectForKey:window];
        DPFadeToolbars(window, NO);
    }
}

void DPPutLittleDiaOver(NSWindow *little, NSWindow *window) {
    if (!little || !window || little == window) return;
    [gOver setObject:little forKey:window];
    DPFadeToolbars(window, YES);
}

void DPInstallLittleDiaOver(void) {
    gOver = [NSMapTable weakToWeakObjectsMapTable];
    for (NSNotificationName name in @[ NSWindowWillCloseNotification, NSWindowWillMiniaturizeNotification ])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (gOver.count && DPIsLittleDiaWindow(note.object)) DPUncover(note.object);
        }];
    NSEventMask clicks = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    [NSEvent addLocalMonitorForEventsMatchingMask:clicks handler:^NSEvent *(NSEvent *event) {
        if (!DPLittleDia.on || !DPLittleDiaIsOver(event.window)) return event;
        [[gOver objectForKey:event.window] performClose:nil];
        return nil;
    }];
}
