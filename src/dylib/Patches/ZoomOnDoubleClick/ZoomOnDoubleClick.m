#import "StdPatch/StdPatch.h"

extern DPPatch DPZoomOnDoubleClick;
static const CGFloat DPBorderReach = 7;  // Dia keeps a 6 point border around the window's content.
static const NSEventModifierFlags DPClickKeys = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift;
static id DPMonitor;

// The frame view's handler follows System Settings for a title bar double-click (fill, zoom, minimise or nothing).
// _zoomWindowWithDoubleClick always zooms, so it isn't used.
static void DPActLikeTitleBar(NSWindow *window, NSView *frame, NSString *action) {
    SEL handler = NSSelectorFromString(@"_handlePossibleDoubleClickWithModifiers:");
    Method method = class_getInstanceMethod(object_getClass(frame), handler);
    char *argument = method && method_getNumberOfArguments(method) == 3 ? method_copyArgumentType(method, 2) : NULL;
    BOOL takesModifiers = argument && !strcmp(argument, @encode(NSUInteger));
    free(argument);
    if (takesModifiers) ((void (*)(id, SEL, NSUInteger))method_getImplementation(method))(frame, handler, 0);
    else if ([action isEqual:@"Minimize"]) [window performMiniaturize:nil];
    else [window performZoom:nil];
}

// Controls, text and the page keep their clicks. In both Dia releases that covers tabs, the tab strip's + button, toolbar
// buttons and the address field, which are all NSControls, plus the few Dia views below that aren't. The toolbar, sidebar
// header and tab strip override mouseDown: too, but the resize border sits over them, so there the click is the window's.
static BOOL DPTakesClicks(NSView *hit, NSWindow *window) {
    static const char *const kept[] = {
        DPDiaTrafficLights, DPDiaPinnedExtension, DPDiaLibraryButton, DPDiaDownloadsButton, DPDiaPageIndicatorDot,
        DPDiaBookmarksBar, DPDiaContentPane, DPDiaSplitPane, DPDiaRenderWidget, NULL,
    };
    NSView *content = window.contentView;
    for (NSView *view = hit; view && view != content && view != content.superview; view = view.superview) {
        if ([view isKindOfClass:NSControl.class] || [view isKindOfClass:NSText.class]) return YES;
        for (const char *const *name = kept; *name; name++)
            if (DPIsKind(view, *name)) return YES;
    }
    return NO;
}

// The first click of a double-click starts Dia's border resize and sits in its tracking loop, which never reaches a
// title bar. A click monitor sees the second click anyway, so that one acts without letting a resize start.
static NSEvent *DPZoomMouse(NSEvent *event) {
    if (!DPZoomOnDoubleClick.on || event.type != NSEventTypeLeftMouseDown || event.clickCount != 2 || (event.modifierFlags & DPClickKeys)) return event;
    NSWindow *window = event.window;
    NSView *frame = window.contentView.superview;
    if (!frame || !DPIsKind(window, DPDiaWindow) || window.attachedSheet || NSApp.modalWindow) return event;
    if ((window.styleMask & NSWindowStyleMaskFullScreen) || !(window.styleMask & NSWindowStyleMaskResizable)) return event;
    NSPoint point = [frame convertPoint:event.locationInWindow fromView:nil];
    CGFloat fromTop = frame.isFlipped ? point.y : NSHeight(frame.bounds) - point.y;
    if (!NSPointInRect(point, frame.bounds) || fromTop > DPBorderReach || DPTakesClicks([frame hitTest:point], window)) return event;
    NSString *action = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleActionOnDoubleClick"];
    if ([action isEqual:@"None"]) return event;
    DPActLikeTitleBar(window, frame, action);
    return nil;
}

static void DPInstallZoomOnDoubleClick(void) {
    DPMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                      handler:^NSEvent *(NSEvent *event) { return DPZoomMouse(event); }];
}

static NSString *DPVerifyZoomOnDoubleClick(DPPatch *patch) {
    return patch->on && !DPMonitor ? @"the double-click monitor isn't installed" : nil;
}

DP_PATCH(DPZoomOnDoubleClick) {
    .key = @"zoomOnDoubleClick",
    .order = 270,
    .title = @"Zoom on Double-Click",
    .detail = @"Double-click the top border of the window to fill or zoom it, like a title bar. Follows the system setting for double-clicking a title bar, and leaves tabs and buttons alone.",
    .symbol = @"arrow.up.left.and.arrow.down.right",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindow),
    .install = DPInstallZoomOnDoubleClick,
    .verify = DPVerifyZoomOnDoubleClick,
};
