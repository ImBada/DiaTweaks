#import "Patches/CommandBar/AutoPip.h"

extern DPPatch DPCommandBar;

// Defer PiP requests during bar-triggered tab round-trips so exitPictureInPicture cancels them while real switches still fire.
static const double DPHoldSeconds = 0.6;
static int DPHolds;
static NSHashTable *DPHeld;

static BOOL DPMediaSession_requestPictureInPicture(id self, SEL _cmd, NSError **error) {
    if (!DPHolds) return DPCallOriginal(DPMediaSession_requestPictureInPicture, self, error);
    [DPHeld addObject:self];
    return YES;
}

static BOOL DPMediaSession_exitPictureInPicture(id self, SEL _cmd, BOOL flag, NSError **error) {
    if (![DPHeld containsObject:self]) return DPCallOriginal(DPMediaSession_exitPictureInPicture, self, flag, error);
    [DPHeld removeObject:self];
    return YES;
}

static void DPReleaseHeld(void) {
    NSArray *sessions = DPHeld.allObjects;
    [DPHeld removeAllObjects];
    SEL _cmd = @selector(requestPictureInPicture:);
    for (id session in sessions) {
        NSError *error;
        DPCallOriginal(DPMediaSession_requestPictureInPicture, session, &error);
    }
}

void DPHoldAutoPip(void) {
    if (!DPCommandBar.on) return;
    DPHolds++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPHoldSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (--DPHolds == 0) DPReleaseHeld();
    });
}

static BOOL DPOverPinnedHeader(NSView *tabList, id gesture) {
    Class headerCls = NSClassFromString(@"DPPinnedHeader");
    if (!headerCls || ![gesture respondsToSelector:@selector(locationInView:)]) return NO;
    NSView *header = DPFindView(tabList, ^BOOL(NSView *view) { return [view isKindOfClass:headerCls]; });
    if (!header || header.isHiddenOrHasHiddenAncestor || !header.superview) return NO;
    return NSPointInRect([gesture locationInView:header.superview], header.frame);
}

static void DPTabList_backgroundDoubleClick(NSView *self, SEL _cmd, id gesture) {
    if (!DPOverPinnedHeader(self, gesture)) DPHoldAutoPip();
    DPCallOriginal(DPTabList_backgroundDoubleClick, self, gesture);
}

static void DPPlusButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPCommandBar.on && DPIsKind(self.superview, DPDiaTabStripTabs)) DPHoldAutoPip();
    DPCallOriginal(DPPlusButton_mouseDown, self, event);
}

void DPInstallAutoPipHold(void) {
    DPHeld = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaMediaSession, @selector(requestPictureInPicture:), (IMP)DPMediaSession_requestPictureInPicture);
    DPHook(DPDiaMediaSession, @selector(exitPictureInPicture:error:), (IMP)DPMediaSession_exitPictureInPicture);
    DPHook(DPDiaTabList, @selector(handleBackgroundDoubleClick:), (IMP)DPTabList_backgroundDoubleClick);
    DPHook(DPDiaTabSurfaceButton, @selector(mouseDown:), (IMP)DPPlusButton_mouseDown);
    [NSNotificationCenter.defaultCenter addObserverForName:NSMenuWillSendActionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (DPCommandBar.on && [[note.userInfo[@"MenuItem"] title] isEqual:@"New Tab"]) DPHoldAutoPip();
    }];
}
