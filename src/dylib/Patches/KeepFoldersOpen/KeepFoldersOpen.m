#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPKeepFoldersOpen;

@interface DPFolderState : NSObject {
@public
    uintptr_t model;
    BOOL known, expanded;
    CFTimeInterval clicked, reopened;
}
@end

@implementation DPFolderState
@end

static char DPStateKey;
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

static void DPClickHeader(NSView *folder) {
    NSView *header = DPTopHeader(folder);
    NSView *target = header ?: folder;
    NSPoint point = [target convertPoint:header ? NSMakePoint(NSMidX(header.bounds), NSMidY(header.bounds)) : NSMakePoint(NSMidX(folder.bounds), 18) toView:nil];
    DPReopening = YES;
    for (NSEventType type = NSEventTypeLeftMouseDown; type <= NSEventTypeLeftMouseUp; type++) {
        NSEvent *event = [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                        windowNumber:folder.window.windowNumber context:nil eventNumber:0 clickCount:1
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
    if (!DPKeepFoldersOpen.on || folders.count != 1 || !folders[0].window || (DPFolderExpanded(folders[0], &expanded) && expanded)) return;
    DPStateOf(folders[0])->reopened = CACurrentMediaTime();
    DPClickHeader(folders[0]);
}

static void DPClearFolder(NSView *folder) {
    if (DPGet(folder, &DPStateKey)) DPSet(folder, &DPStateKey, nil);
}

static void DPCheckFolder(NSView *folder) {
    if (!DPKeepFoldersOpen.on) return DPClearFolder(folder);
    BOOL expanded;
    if (!DPFolderExpanded(folder, &expanded) || !folder.window) return;
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
    if (!DPCollapsedFolders.count)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{ DPReopenFolders(); });
    [DPCollapsedFolders addObject:folder];
}

static void DPFolder_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFolder_layout, self);
    DPCheckFolder(self);
}

static void DPFolder_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPKeepFoldersOpen.on && !DPReopening) DPStateOf(self)->clicked = CACurrentMediaTime();
    DPCallOriginal(DPFolder_mouse, self, event);
}

static void DPHeader_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPKeepFoldersOpen.on && !DPReopening) {
        NSView *folder = self.superview;
        while (folder && !DPIsKind(folder, DPDiaTabGroupView)) folder = folder.superview;
        if (folder) DPStateOf(folder)->clicked = CACurrentMediaTime();
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
    DPHook(DPDiaTabGroupCell, @selector(mouseUp:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(prepareForReuse), (IMP)DPFolder_prepareForReuse);
    DPHook(DPDiaTabGroupView, @selector(layout), (IMP)DPFolder_layout);
    DPHook(DPDiaTabGroupHeader, @selector(mouseDown:), (IMP)DPHeader_mouse);
    DPHook(DPDiaTabGroupHeader, @selector(mouseUp:), (IMP)DPHeader_mouse);
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
