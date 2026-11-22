#import "Patches/Peek/Peek.h"
#import "Patches/CommandBar/Tabs.h"
#import <dlfcn.h>

static char DPPeekCoverKey;
typedef CGImageRef (*DPPeekWindowCapture)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);

static DPPeekWindowCapture DPPeekCaptureOwnWindow(void) {
    static DPPeekWindowCapture capture;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Obsoleted in the SDK, but the runtime still captures this app's own window without screen recording access.
        capture = dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    });
    return capture;
}

@interface DPPeekCover : NSWindow
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, weak) NSView *destination;
@property (nonatomic, copy) NSString *originTabID, *destinationTabID;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, copy) void (^promote)(void);
@property (nonatomic) NSUInteger visibleFrames;
@property (nonatomic) BOOL presented;
- (void)dismiss;
@end

@implementation DPPeekCover
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

- (void)dismiss {
    void (^promote)(void) = self.promote;
    self.promote = nil;
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self orderOut:nil];
    [self.parentWindow removeChildWindow:self];
    DPPeekCard *peek = self.peek;
    if (peek && DPGet(peek, &DPPeekCoverKey) == self) DPSet(peek, &DPPeekCoverKey, nil);
    DPPeekUpdateSyncTimer();
    if (promote) promote();
}

- (void)step:(CADisplayLink *)link {
    if (self.promote) {
        // Commit a frame with the child window before native tab selection starts.
        if (!self.presented) {
            self.presented = YES;
            return;
        }
        void (^promote)(void) = self.promote;
        self.promote = nil;
        promote();
        return;
    }
    NSView *destination = self.destination;
    NSWindow *parent = self.parentWindow;
    if (!parent.isVisible) return [self dismiss];
    BOOL visible = destination.window == parent && !destination.isHiddenOrHasHiddenAncestor && !NSIsEmptyRect(destination.visibleRect);
    self.visibleFrames = visible ? self.visibleFrames + 1 : 0;
    // Give Chromium's remote compositor two presentations before uncovering the new tab.
    if (self.visibleFrames >= 3) [self dismiss];
}
@end

static DPPeekCover *DPPeekCoverIn(NSWindow *window) {
    for (NSWindow *child in window.childWindows)
        if ([child isKindOfClass:DPPeekCover.class]) return (DPPeekCover *)child;
    return nil;
}

BOOL DPPeekHandoffActive(void) {
    for (NSWindow *window in NSApp.windows)
        if (DPPeekCoverIn(window)) return YES;
    return NO;
}

void DPPeekHandoffSync(void) {
    for (NSWindow *window in [NSApp.windows copy]) {
        if (!DPPeekCoverIn(window)) continue;
        NSString *active = DPActiveTabID(window);
        if (active) DPPeekHandoffSelectionChanged(window, active);
    }
}

void DPPeekCancelHandoffs(void) {
    for (NSWindow *window in [NSApp.windows copy])
        for (NSWindow *child in [window.childWindows copy]) {
            if (![child isKindOfClass:DPPeekCover.class]) continue;
            DPPeekCover *cover = (DPPeekCover *)child;
            cover.promote = nil;
            [cover dismiss];
        }
}

void DPPeekCompleteHandoff(DPPeekCard *peek, NSView *destination) {
    DPPeekCover *cover = DPGet(peek, &DPPeekCoverKey);
    DPSet(peek, &DPPeekCoverKey, nil);
    if (cover.parentWindow && destination) {
        cover.destination = destination;
        NSString *active = DPActiveTabID(cover.parentWindow);
        if (active && ![active isEqual:cover.originTabID]) cover.destinationTabID = active;
    } else [cover dismiss];
}

void DPPeekHandoffSelectionChanged(NSWindow *window, NSString *active) {
    for (NSWindow *child in [window.childWindows copy]) {
        if (![child isKindOfClass:DPPeekCover.class]) continue;
        DPPeekCover *cover = (DPPeekCover *)child;
        if (active && [active isEqual:cover.destinationTabID ?: cover.originTabID]) continue;
        if (active && !cover.promote && !cover.destination && DPPeekGiving) {
            // Selecting the tab Dia is adopting this Peek into is part of the promotion.
            cover.destinationTabID = active;
            continue;
        }
        void (^promote)(void) = active ? cover.promote : nil;
        cover.promote = nil;
        [cover dismiss];
        if (promote) dispatch_async(dispatch_get_main_queue(), promote);
    }
}

static void DPPeekShowCover(DPPeekCard *peek, CGImageRef contents, void (^promote)(void)) {
    NSWindow *parent = peek.window;
    if (!parent.isVisible || peek.isHiddenOrHasHiddenAncestor || !contents) return promote();
    NSRect frame = [parent convertRectToScreen:[peek convertRect:peek.bounds toView:nil]];
    DPPeekCover *cover = [[DPPeekCover alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered defer:NO];
    cover.opaque = NO;
    cover.backgroundColor = NSColor.clearColor;
    cover.hasShadow = NO;
    cover.ignoresMouseEvents = YES;
    cover.excludedFromWindowsMenu = YES;
    cover.restorable = NO;
    cover.releasedWhenClosed = NO;
    cover.animationBehavior = NSWindowAnimationBehaviorNone;
    cover.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSView *content = [[NSView alloc] initWithFrame:(NSRect){NSZeroPoint, frame.size}];
    CALayer *layer = [CALayer layer];
    layer.frame = content.bounds;
    layer.contentsScale = parent.backingScaleFactor;
    layer.contents = (__bridge id)contents;
    content.layer = layer;
    content.wantsLayer = YES;
    cover.contentView = content;
    cover.peek = peek;
    cover.promote = promote;
    cover.originTabID = peek.originTabID;
    DPSet(peek, &DPPeekCoverKey, cover);
    [parent addChildWindow:cover ordered:NSWindowAbove];
    cover.displayLink = [parent displayLinkWithTarget:cover selector:@selector(step:)];
    [cover.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    DPPeekUpdateSyncTimer();
    // A hidden or switched-away destination may never get its display ticks.
    __weak DPPeekCover *weak = cover;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DPPeekCover *cover = weak;
        if (cover.displayLink) [cover dismiss];
    });
}

void DPPeekPrepareHandoff(DPPeekCard *peek, void (^complete)(void)) {
    NSWindow *window = peek.window;
    NSScreen *primary = NSScreen.screens.firstObject;
    DPPeekWindowCapture capture = DPPeekCaptureOwnWindow();
    // An occluded window has nothing to bridge, and its image would be stale.
    if (!capture || !primary || !window.isVisible || !(window.occlusionState & NSWindowOcclusionStateVisible) ||
        peek.isHiddenOrHasHiddenAncestor || window.windowNumber <= 0 || window.sharingType == NSWindowSharingNone) return complete();
    NSRect frame = [window convertRectToScreen:[peek convertRect:peek.bounds toView:nil]];
    if (NSIsEmptyRect(frame)) return complete();
    CGRect screenBounds = CGRectMake(NSMinX(frame), NSMaxY(primary.frame) - NSMaxY(frame), NSWidth(frame), NSHeight(frame));
    CGWindowID windowID = (CGWindowID)window.windowNumber;
    [CATransaction flush];  // Include the expanded Peek in the WindowServer image.
    __block BOOL done = NO;
    void (^finish)(CGImageRef) = ^(CGImageRef image) {
        if (done) return;
        done = YES;
        if (peek.window == window) DPPeekShowCover(peek, image, complete);
        else complete();
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 70 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ finish(NULL); });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        CGImageRef image = capture(screenBounds, kCGWindowListOptionIncludingWindow, windowID, kCGWindowImageBestResolution);
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(image);
            if (image) CGImageRelease(image);
        });
    });
}
