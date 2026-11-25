#import "StdPatch/Hide.h"
#include <stdatomic.h>
#include <dlfcn.h>

NSHashTable<NSView *> *DPHideHosts, *DPSuppressed;
static char DPHidersKey, DPHidersUnmatchedKey;
static DPPatch **DPHidePatches;
static NSUInteger DPHidePatchCount;
static DPPatch *const *DPHideSource;
static NSUInteger DPHideSourceCount;
static BOOL DPAnyHideOn;
// Bumped when the rules themselves change, which is what makes a cached miss worth re-checking.
static _Atomic(uint32_t) DPHidesGeneration = 1;

@interface DPHideMiss : NSObject {
@public
    uint32_t _generation;
    NSUInteger _subviews;
    const void *_superview;
    NSString *_label;
}
@end

@implementation DPHideMiss
@end

static void DPSyncAnyHidesOn(void) {
    BOOL any = NO;
    for (NSUInteger i = 0; i < DPHidePatchCount && !any; i++) any = DPHidePatches[i]->on;
    DPAnyHideOn = any;
}

static void DPCacheHidePatches(void) {
    if (DPHideSource == DPPatches && DPHideSourceCount == DPPatchCount) return;
    free(DPHidePatches);
    DPHidePatches = DPPatchCount ? calloc(DPPatchCount, sizeof *DPHidePatches) : NULL;
    DPHidePatchCount = 0;
    DPHideSource = DPPatches;
    DPHideSourceCount = DPPatchCount;
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->hides) DPHidePatches[DPHidePatchCount++] = DPPatches[i];
    DPSyncAnyHidesOn();
    atomic_fetch_add(&DPHidesGeneration, 1);
}

BOOL DPAnyHidesOn(void) {
    if (DPHideSource == DPPatches && DPHideSourceCount == DPPatchCount && !DPTesting) return DPAnyHideOn;
    DPCacheHidePatches();
    DPSyncAnyHidesOn();
    return DPAnyHideOn;
}

// A layout pass asks about every view in a hide host, so a miss is remembered until its label, subviews or parent
// changes; capsule buttons and upsell bars inspect inner controls or text that can mutate later, so they re-run.
static NSArray<NSValue *> *DPHiders(NSView *view) {
    NSArray<NSValue *> *cached = DPGet(view, &DPHidersKey);
    if (cached) return cached;
    DPCacheHidePatches();
    DPShareLabel(view);
    DPHideMiss *miss = DPGet(view, &DPHidersUnmatchedKey);
    uint32_t generation = atomic_load_explicit(&DPHidesGeneration, memory_order_relaxed);
    NSUInteger subviewCount = view.subviews.count;
    const void *superview = (__bridge const void *)view.superview;
    NSString *label = DPSharedLabel(view) ?: @"";
    if (miss && miss->_generation == generation && miss->_subviews == subviewCount && miss->_superview == superview
        && [miss->_label isEqualToString:label]) {
        DPShareLabel(nil);
        return nil;
    }
    NSMutableArray<NSValue *> *hiders = nil;
    for (NSUInteger i = 0; i < DPHidePatchCount; i++) {
        DPPatch *patch = DPHidePatches[i];
        if (patch->unavailable || !patch->hides(view)) continue;
        if (!hiders) hiders = [NSMutableArray array];
        [hiders addObject:[NSValue valueWithPointer:patch]];
    }
    DPShareLabel(nil);
    if (hiders) {
        DPSet(view, &DPHidersKey, hiders);
        if (miss) DPSet(view, &DPHidersUnmatchedKey, nil);
    } else if (!DPIsKind(view, DPDiaCapsuleButton) && !DPIsKind(view, DPDiaAppsUpsellBar)) {
        if (!miss) {
            miss = [DPHideMiss new];
            DPSet(view, &DPHidersUnmatchedKey, miss);
        }
        miss->_generation = generation;
        miss->_subviews = subviewCount;
        miss->_superview = superview;
        miss->_label = [label copy];
    }
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
    DPCacheHidePatches();
    DPSyncAnyHidesOn();
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
