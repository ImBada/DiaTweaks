#import "HideToolbar.h"
#import <objc/message.h>

typedef NS_ENUM(NSInteger, DPWebContentsVisibility) { DPWebContentsVisible = 2 };

static NSHashTable *DPLoadingContents;
static NSTimer *DPProgressTimer;
static char DPProgressKey;

static BOOL DPPaneLoading(NSView *pane) {
    NSView *reload = DPFindView(DPSubview(pane, DPDiaToolbar), ^BOOL(NSView *view) { return DPIsKind(view, DPDiaReloadIcon); });
    BOOL *loading = DPIvar(reload, "isLoading");
    return loading && *loading;
}

static id DPVisibleLoadingContents(void) {
    id best = nil;
    for (id contents in DPLoadingContents.allObjects) {
        if (((NSInteger (*)(id, SEL))objc_msgSend)(contents, @selector(visibility)) != DPWebContentsVisible) continue;
        if (!best || ((BOOL (*)(id, SEL))objc_msgSend)(contents, @selector(hasFocus))) best = contents;
    }
    return best;
}

static BOOL DPToolbarOutOfSight(NSView *pane) {
    DPToolbarHover *hover = [DPToolbarHover forPane:pane];
    return DPHideToolbar.on && DPHideToolbar.progress == 1 && hover.bar && !hover.bar.hiddenOrHasHiddenAncestor &&
           hover.progress == 0 && hover.inPlaceProgress == 0;
}

static BOOL DPLoadingProgressOn(void) { return DPHideToolbar.on && DPShowLoadingProgress.on; }

static void DPRefreshProgress(void) {
    BOOL on = DPLoadingProgressOn();
    id contents = on ? DPVisibleLoadingContents() : nil;
    CGFloat progress = contents ? [DPGet(contents, &DPProgressKey) doubleValue] : 1;
    BOOL loading = NO;
    for (NSView *pane in DPPanes) {
        BOOL inSight = on && pane.window && !pane.hiddenOrHasHiddenAncestor, paneLoading = inSight && DPPaneLoading(pane);
        if (!inSight || !DPToolbarOutOfSight(pane)) DPRemoveProgressLine(pane);
        else if (paneLoading) DPShowProgressLine(pane, MAX(0.1, progress));
        else DPFinishProgressLine(pane);
        loading = loading || paneLoading;
    }
    // The reload button changes after Chromium's own updates, so poll.
    BOOL watch = on && (loading || contents);
    if (watch && !DPProgressTimer) {
        DPProgressTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { DPRefreshProgress(); }];
        [NSRunLoop.mainRunLoop addTimer:DPProgressTimer forMode:NSRunLoopCommonModes];
    } else if (!watch) {
        [DPProgressTimer invalidate];
        DPProgressTimer = nil;
    }
}

static void DPContents_setIsLoading(id self, SEL _cmd, BOOL loading) {
    DPCallOriginal(DPContents_setIsLoading, self, loading);
    if (loading) [DPLoadingContents addObject:self];
    else [DPLoadingContents removeObject:self];
    if (DPLoadingProgressOn()) DPRefreshProgress();
}

static void DPContents_setLoadProgress(id self, SEL _cmd, double progress) {
    DPCallOriginal(DPContents_setLoadProgress, self, progress);
    DPSet(self, &DPProgressKey, @(progress));
    if (DPLoadingProgressOn()) DPRefreshProgress();
}

static void DPInstallLoadingProgress(void) {
    DPLoadingContents = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaWebContents, @selector(setIsLoading:), (IMP)DPContents_setIsLoading);
    DPHook(DPDiaWebContents, @selector(setLoadProgress:), (IMP)DPContents_setLoadProgress);
    [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *_) {
        DPRefreshProgress();
    }];
    DPInstallProgressColors();
}

static void DPApplyLoadingProgress(DPPatch *patch) { DPRefreshProgress(); }

static NSString *DPVerifyLoadingProgress(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        if (!DPShowsProgressLine(pane)) continue;
        if (!patch->on) return @"progress line left on the page";
        if (!DPToolbarOutOfSight(pane)) return @"progress line shows with the toolbar";
    }
    return nil;
}

DP_PATCH(DPShowLoadingProgress) {
    .key = @"showLoadingProgress",
    .defaultOn = YES,
    .order = 43,
    .title = @"Show Loading Progress",
    .detail = @"Show Dia’s loading glow along the top of the page while it loads, where the hidden toolbar would show it.",
    .symbol = @"rectangle.topthird.inset.filled",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"While It’s Hidden",
    .classes = DPClasses(DPDiaWebContents, DPDiaReloadIcon),
    .choice = @"loadingProgressColor",
    .defaultChoice = @"dia",
    .choices = DPProgressColorChoices,
    .install = DPInstallLoadingProgress,
    .apply = DPApplyLoadingProgress,
    .verify = DPVerifyLoadingProgress,
};
