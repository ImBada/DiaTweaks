#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPKeepFoldersOpen;

@interface DPFolderState : NSObject {
@public
    uintptr_t model;
    BOOL known, expanded, wasVisible, hasDown, dragged;
    NSPoint down;
    CFTimeInterval clicked, reopened;
}
@end

@implementation DPFolderState
@end

static char DPStateKey, DPClosedWindowKey;
static NSHashTable<NSView *> *DPCollapsedFolders;
static BOOL DPReopening;

static id DPObjectIvar(id object, const char *name) {
    void *slot = DPIvar(object, name);
    return slot ? *(__unsafe_unretained id *)slot : nil;
}

static NSView *DPTopHeader(NSView *folder) {
    id header = DPObjectIvar(folder, "$__lazy_storage_$_headerView");
    return [header isKindOfClass:NSView.class] ? header : nil;
}

static BOOL DPFolderExpanded(NSView *folder, BOOL *expanded) {
    if (DPIsKind(folder, DPDiaTabGroupView)) {
        BOOL *flag = DPIvar(folder, "shouldDisplayExpandedContainer");
        if (flag) *expanded = *flag;
        return flag != NULL;
    }
    id chevron = DPObjectIvar(folder, "$__lazy_storage_$_chevronIconView");
    CALayer *layer = [chevron isKindOfClass:NSView.class] ? ((NSView *)chevron).layer : nil;
    if (layer) *expanded = fabs(atan2(layer.transform.m12, layer.transform.m11)) < 0.1;
    return layer != nil;
}

static DPFolderState *DPStateOf(NSView *folder) {
    DPFolderState *state = DPGet(folder, &DPStateKey);
    if (!state) DPSet(folder, &DPStateKey, state = [DPFolderState new]);
    return state;
}

static BOOL DPWindowAlive(NSWindow *window, BOOL wasVisible) {
    return window && window.windowNumber > 0 && !DPGet(window, &DPClosedWindowKey) && (!wasVisible || window.isVisible);
}

static void DPClickHeader(NSView *folder) {
    NSWindow *window = folder.window;
    if (!folder.superview || !DPWindowAlive(window, DPStateOf(folder)->wasVisible)) return;
    NSView *header = DPTopHeader(folder);
    NSView *target = header ?: folder;
    NSPoint point = [target convertPoint:header ? NSMakePoint(NSMidX(header.bounds), NSMidY(header.bounds)) : NSMakePoint(NSMidX(folder.bounds), 18) toView:nil];
    DPReopening = YES;
    for (NSEventType type = NSEventTypeLeftMouseDown; type <= NSEventTypeLeftMouseUp; type++) {
        NSWindow *live = target.window;
        if (live != window || !DPWindowAlive(live, DPStateOf(folder)->wasVisible)) break;
        NSEvent *event = [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                        windowNumber:live.windowNumber context:nil eventNumber:0 clickCount:1
                                            pressure:type == NSEventTypeLeftMouseDown];
        if (type == NSEventTypeLeftMouseDown) [target mouseDown:event];
        else [target mouseUp:event];
    }
    DPReopening = NO;
}

static void DPReopenFolders(void) {
    NSArray<NSView *> *folders = DPCollapsedFolders.allObjects;
    [DPCollapsedFolders removeAllObjects];
    // Multiple collapses at once mean collapse-all, not an emptied folder.
    BOOL expanded = NO;
    NSView *folder = folders.count == 1 ? folders[0] : nil;
    if (!DPKeepFoldersOpen.on || !folder || !folder.superview || !DPWindowAlive(folder.window, DPStateOf(folder)->wasVisible)
        || (DPFolderExpanded(folder, &expanded) && expanded)) return;
    DPStateOf(folder)->reopened = CACurrentMediaTime();
    DPClickHeader(folder);
}

static void DPClearFolder(NSView *folder) {
    if (DPGet(folder, &DPStateKey)) DPSet(folder, &DPStateKey, nil);
}

static void DPCheckFolder(NSView *folder) {
    if (!DPKeepFoldersOpen.on) return DPClearFolder(folder);
    BOOL expanded;
    NSWindow *window = folder.window;
    if (!DPFolderExpanded(folder, &expanded) || !DPWindowAlive(window, NO)) return;
    DPFolderState *state = DPStateOf(folder);
    uintptr_t model = (uintptr_t)DPObjectIvar(folder, "viewModel");
    if (model != state->model) {
        if (model) state->known = NO;
        state->model = model;
    }
    BOOL collapsed = state->known && state->expanded && !expanded;
    state->known = YES;
    state->expanded = expanded;
    CFTimeInterval now = CACurrentMediaTime();
    if (!collapsed || now - state->clicked < 1) return;
    if (now - DPFoldedAt < 2) return;
    if (now - state->reopened < 1) return;
    state->wasVisible = window.isVisible;
    if (!DPCollapsedFolders.count)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{ DPReopenFolders(); });
    [DPCollapsedFolders addObject:folder];
}

static void DPFolder_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFolder_layout, self);
    DPCheckFolder(self);
}

static BOOL DPInFolderToggle(NSView *cell, NSEvent *event) {
    NSPoint local = [cell convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(local, cell.bounds)) return NO;
    BOOL sawHeader = NO;
    for (NSView *sub in cell.subviews) {
        if (DPIsKind(sub, DPDiaTabGroupBackground)) continue;
        sawHeader = YES;
        if (NSPointInRect([sub convertPoint:event.locationInWindow fromView:nil], sub.bounds)) return YES;
    }
    if (sawHeader) return NO;
    return cell.isFlipped ? local.y <= 40 : local.y >= NSHeight(cell.bounds) - 40;
}

static void DPTrackClick(DPFolderState *state, SEL cmd, NSEvent *event, BOOL inToggle) {
    NSPoint where = event.locationInWindow;
    if (cmd == @selector(mouseDown:)) {
        state->hasDown = inToggle;
        state->dragged = NO;
        state->down = where;
        state->clicked = inToggle ? CACurrentMediaTime() : 0;
    } else if (cmd == @selector(mouseDragged:)) {
        if (!state->hasDown || hypot(where.x - state->down.x, where.y - state->down.y) > 4) {
            state->dragged = YES;
            state->clicked = 0;
        }
    } else if (cmd == @selector(mouseUp:)) {
        BOOL dragged = state->dragged || (state->hasDown && hypot(where.x - state->down.x, where.y - state->down.y) > 4);
        state->hasDown = state->dragged = NO;
        state->clicked = (!dragged && inToggle) ? CACurrentMediaTime() : 0;
    }
}

static void DPFolder_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPKeepFoldersOpen.on && !DPReopening) DPTrackClick(DPStateOf(self), _cmd, event, DPInFolderToggle(self, event));
    DPCallOriginal(DPFolder_mouse, self, event);
}

static void DPHeader_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPKeepFoldersOpen.on && !DPReopening) {
        NSView *folder = self.superview;
        while (folder && !DPIsKind(folder, DPDiaTabGroupView)) folder = folder.superview;
        BOOL inHeader = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
        if (folder) DPTrackClick(DPStateOf(folder), _cmd, event, inHeader);
    }
    DPCallOriginal(DPHeader_mouse, self, event);
}

static void DPFolder_prepareForReuse(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFolder_prepareForReuse, self);
    DPFolderState *state = DPGet(self, &DPStateKey);
    if (!state) return;
    state->known = NO;
    state->model = 0;
}

static void DPApplyKeepFoldersOpen(DPPatch *patch) {
    if (!patch->on) [DPCollapsedFolders removeAllObjects];
    const char *names[] = { DPDiaTabGroupCell, DPDiaTabGroupView, NULL };
    for (const char **name = names; *name; name++) {
        Class cls = objc_getClass(*name);
        if (!cls) continue;
        for (NSWindow *window in NSApp.windows)
            DPFindView(window.contentView, ^BOOL(NSView *view) {
                if ([view isKindOfClass:cls]) {
                    if (patch->on) DPCheckFolder(view);
                    else DPClearFolder(view);
                }
                return NO;
            });
    }
}

static void DPInstallKeepFoldersOpen(void) {
    DPCollapsedFolders = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabGroupCell, @selector(layout), (IMP)DPFolder_layout);
    DPHook(DPDiaTabGroupCell, @selector(mouseDown:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(mouseDragged:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(mouseUp:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(prepareForReuse), (IMP)DPFolder_prepareForReuse);
    DPHook(DPDiaTabGroupView, @selector(layout), (IMP)DPFolder_layout);
    DPHook(DPDiaTabGroupHeader, @selector(mouseDown:), (IMP)DPHeader_mouse);
    DPHook(DPDiaTabGroupHeader, @selector(mouseDragged:), (IMP)DPHeader_mouse);
    DPHook(DPDiaTabGroupHeader, @selector(mouseUp:), (IMP)DPHeader_mouse);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:NSWindow.class]) DPSet(note.object, &DPClosedWindowKey, @YES);
    }];
}

DP_PATCH(DPKeepFoldersOpen) {
    .key = @"keepFoldersOpen",
    .order = 79,
    .title = @"Keep Folders Open",
    .detail = @"Stop folders collapsing on their own when they empty, in the sidebar or at the top, so new tabs and live folder items show up.",
    .symbol = @"folder.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupView, DPDiaTabGroupHeader),
    .install = DPInstallKeepFoldersOpen,
    .apply = DPApplyKeepFoldersOpen,
};
