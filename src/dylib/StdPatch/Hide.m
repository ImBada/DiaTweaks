#import "StdPatch/Hide.h"
#import <dlfcn.h>

NSHashTable<NSView *> *DPHideHosts, *DPSuppressed;
static char DPHidersKey;
static DPPatch **DPHidePatches;
static NSUInteger DPHidePatchCount;
static DPPatch *const *DPHideSource;
static NSUInteger DPHideSourceCount;

static void DPCacheHidePatches(void) {
    if (DPHideSource == DPPatches && DPHideSourceCount == DPPatchCount) return;
    free(DPHidePatches);
    DPHidePatches = DPPatchCount ? calloc(DPPatchCount, sizeof *DPHidePatches) : NULL;
    DPHidePatchCount = 0;
    DPHideSource = DPPatches;
    DPHideSourceCount = DPPatchCount;
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->hides) DPHidePatches[DPHidePatchCount++] = DPPatches[i];
}

BOOL DPAnyHidesOn(void) {
    DPCacheHidePatches();
    for (NSUInteger i = 0; i < DPHidePatchCount; i++)
        if (DPHidePatches[i]->on) return YES;
    return NO;
}

// Only a match is cached: some views only match once Dia labels them.
static NSArray<NSValue *> *DPHiders(NSView *view) {
    NSArray<NSValue *> *cached = DPGet(view, &DPHidersKey);
    if (cached) return cached;
    DPCacheHidePatches();
    NSMutableArray<NSValue *> *hiders = nil;
    DPShareLabel(view);
    for (NSUInteger i = 0; i < DPHidePatchCount; i++) {
        DPPatch *patch = DPHidePatches[i];
        if (patch->unavailable || !patch->hides(view)) continue;
        if (!hiders) hiders = [NSMutableArray array];
        [hiders addObject:[NSValue valueWithPointer:patch]];
    }
    DPShareLabel(nil);
    if (hiders) DPSet(view, &DPHidersKey, hiders);
    return hiders;
}

DPPatch *DPHider(NSView *view) {
    NSArray<NSValue *> *hiders = DPHiders(view);
    for (NSValue *hider in hiders)
        if (((DPPatch *)hider.pointerValue)->on) return hider.pointerValue;
    return hiders.firstObject.pointerValue;
}

static DPPatch *DPActiveHider(NSView *view) {
    DPPatch *hider = DPHider(view);
    return hider && hider->on ? hider : NULL;
}

static void DPHidden_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    BOOL suppress = !hidden && DPAnyHidesOn() && DPActiveHider(self);
    if (suppress) [DPSuppressed addObject:self];
    else [DPSuppressed removeObject:self];
    DPCallOriginal(DPHidden_setHidden, self, hidden || suppress);
}

// Before the window shows, Dia only hides views that report visible, so lie to Dia's code then.
static BOOL DPHidden_isHidden(NSView *self, SEL _cmd) {
    Dl_info caller;
    if (!self.window.isVisible && [DPSuppressed containsObject:self] && dladdr(__builtin_return_address(0), &caller)
        && caller.dli_fname && strstr(caller.dli_fname, "/Dia.app/"))
        return NO;
    return DPCallOriginal(DPHidden_isHidden, self);
}

static void DPHidden_viewDidMoveToWindow(NSView *self, SEL _cmd);

static void DPEnforce(NSView *view) {
    DPHookClass(view.class, @selector(viewDidMoveToWindow), (IMP)DPHidden_viewDidMoveToWindow);
    DPHookClass(view.class, @selector(setHidden:), (IMP)DPHidden_setHidden);
    DPHookClass(view.class, @selector(isHidden), (IMP)DPHidden_isHidden);
    if (!view.hidden) DPHidden_setHidden(view, @selector(setHidden:), NO);
}

static void DPHidden_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPHidden_viewDidMoveToWindow, self);
    if (DPActiveHider(self)) DPEnforce(self);
}

static void DPEnforceHidesIn(NSView *root) {
    if (DPActiveHider(root)) return DPEnforce(root);
    for (NSView *sub in root.subviews) DPEnforceHidesIn(sub);
}

void DPEnforceHides(NSView *root) {
    if (DPAnyHidesOn()) DPEnforceHidesIn(root);
}

void DPApplyHides(DPPatch *patch) {
    if (patch->on) for (NSView *host in DPHideHosts.allObjects) DPEnforceHides(host);
    else for (NSView *view in DPSuppressed.allObjects) if (!DPActiveHider(view)) view.hidden = NO;
    DPRelayoutViews(DPHideHosts);
}

static NSString *DPProblem(NSView *view, DPPatch *patch) {
    if ([DPHiders(view) containsObject:[NSValue valueWithPointer:patch]]) {
        if (patch->on && !view.hiddenOrHasHiddenAncestor) return @"button still shows";
        return !DPActiveHider(view) && [DPSuppressed containsObject:view] ? @"button still hidden" : nil;
    }
    for (NSView *sub in view.subviews) {
        NSString *problem = DPProblem(sub, patch);
        if (problem) return problem;
    }
    return nil;
}

NSString *DPVerifyHides(DPPatch *patch) {
    NSHashTable<NSView *> *hosts = [DPHideHosts copy];
    for (const char *const *name = DPHideHostClasses; *name; name++) for (NSView *host in DPFindViews(*name)) [hosts addObject:host];
    if (!hosts.count) return @"no toolbar or tab bar found";
    for (NSView *host in hosts) {
        NSString *problem = host.window.isVisible ? DPProblem(host, patch) : nil;
        if (problem) return problem;
    }
    return nil;
}

void DPInstallHides(void) {
    DPHideHosts = [NSHashTable weakObjectsHashTable];
    DPSuppressed = [NSHashTable weakObjectsHashTable];
    DPCacheHidePatches();
    if (DPHidePatchCount) DPInstallHideHosts();
}
