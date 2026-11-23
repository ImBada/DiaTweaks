#import <AppKit/AppKit.h>
#import "Patches/HideToolbar/HideToolbar.h"

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
DPPatch DPPeek;

static BOOL gAppActive = YES, gLittleDiaOver;
static NSWindow *gKeyWindow;
static NSPoint gMouse;

static BOOL DPApp_isActive(NSApplication *self, SEL _cmd) { return gAppActive; }
static BOOL DPWindow_isKeyWindow(NSWindow *self, SEL _cmd) { return self == gKeyWindow; }
static NSPoint DPEvent_mouseLocation(NSEvent *self, SEL _cmd) { return gMouse; }

BOOL DPBesideSidebar(NSView *container) { return NO; }
BOOL DPLittleDiaIsOver(NSWindow *window) { return gLittleDiaOver; }
void DPRepaintTabs(NSWindow *window) {}
NSString *DPChoice(DPPatch *patch) { return @"dia"; }

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (BOOL)isFlipped { return YES; }
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC11BookmarkBar15BookmarkBarView : NSView
@end
@implementation _TtC11BookmarkBar15BookmarkBarView
@end

@interface DPFocusView : NSView
@end
@implementation DPFocusView
- (BOOL)acceptsFirstResponder { return YES; }
@end

#import "Patches/HideToolbar/HideToolbar.m"
#import "Patches/HideToolbar/Layout.m"
#import "Patches/HideToolbar/Hover.m"
#import "Patches/HideToolbar/Permission.m"
#import "Patches/HideToolbar/RevealOnHover.m"
#import "Patches/HideToolbar/KeepBookmarks.m"
#import "Patches/HideToolbar/ShowWithSidebar.m"
#import "Patches/HideToolbar/ShowOnNewTab.m"
#import "Patches/HideToolbar/ShowWithTopTabs.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void PumpUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(NSApp.class, @selector(isActive), (IMP)DPApp_isActive);
        DPHookClass(NSWindow.class, @selector(isKeyWindow), (IMP)DPWindow_isKeyWindow);
        DPHookClass(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)DPEvent_mouseLocation);

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        DPRevealToolbarOnHover.on = NO;
        DPShowToolbarWithSidebar.on = NO;
        DPShowToolbarOnNewTab.on = NO;
        DPShowToolbarWithTopTabs.on = NO;
        DPKeepBookmarksBar.on = NO;
        DPHideToolbar.install();

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 800, 600)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        gKeyWindow = window;
        _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        _TtC13NavigationBar17NavigationBarView *bar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, 44)];
        _TtC11BookmarkBar15BookmarkBarView *bookmarks = [[_TtC11BookmarkBar15BookmarkBarView alloc] initWithFrame:NSMakeRect(0, 44, 800, 28)];
        NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 72, 800, 528)];
        [pane addSubview:bar];
        [pane addSubview:bookmarks];
        [pane addSubview:page];
        [window.contentView addSubview:pane];

        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        DPRevealToolbarOnHover.on = YES;
        [pane layout];
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        CHECK(hover != nil, "hover attached");
        CHECK(hover.paneTracking != nil, "whole-pane tracking area added for overshoot");
        CHECK(!hover.revealed && bar.alphaValue == 0, "toolbar hidden at rest");

        gMouse = NSMakePoint(500, 810);  // just above the window's top edge (800)
        CHECK([hover pointerAbovePage], "a pointer just above the window counts as overshoot");
        gMouse = NSMakePoint(500, 900);  // far above the window, e.g. another display
        CHECK(![hover pointerAbovePage], "a pointer far above the window isn't overshoot");
        gMouse = NSMakePoint(500, 810);
        [hover mouseExited:nil];
        CHECK(hover.revealed, "overshoot above the page reveals the toolbar");
        CHECK(hover.hideTimer != nil, "hide timer armed while the pointer is above the page");

        gMouse = NSMakePoint(500, 400);
        PumpUntil(^{ return (BOOL)!hover.revealed; });
        CHECK(!hover.revealed, "moving back down hides the toolbar");

        DPRevealToolbarOnHover.on = NO;
        [pane layout];
        hover = [DPToolbarHover forPane:pane];
        CHECK(hover.tracking == nil, "no hover strip when Show Toolbar on Hover is off");
        CHECK(!hover.revealed, "toolbar hidden before focus");

        DPFocusView *field = [[DPFocusView alloc] initWithFrame:NSMakeRect(10, 10, 100, 20)];
        [bar addSubview:field];
        [window makeFirstResponder:field];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidUpdateNotification object:window];
        CHECK(hover.revealed, "focus in the hidden bar reveals the toolbar");
        CHECK(hover.hideTimer != nil, "hide timer armed while the bar has focus");

        [window makeFirstResponder:page];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidUpdateNotification object:window];
        PumpUntil(^{ return (BOOL)!hover.revealed; });
        CHECK(!hover.revealed, "losing focus hides the toolbar");

        gKeyWindow = nil;
        [window makeFirstResponder:field];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidUpdateNotification object:window];
        CHECK(!hover.revealed, "a background window doesn't reveal its toolbar");
        gKeyWindow = window;

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        [pane layout];
        [window makeFirstResponder:field];
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidUpdateNotification object:window];
        CHECK(!hover.revealed, "no reveal when Hide Toolbar is off");
        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        [pane layout];

        DPRevealToolbarOnHover.on = NO;
        DPKeepBookmarksBar.on = YES;
        [pane layout];
        hover = [DPToolbarHover forPane:pane];
        CHECK(bookmarks.alphaValue == 1, "bookmarks stay visible while the toolbar hides");
        CHECK(bar.alphaValue == 0, "toolbar still hides");
        CHECK(NSMinY(bookmarks.frame) == 0, "bookmarks move up to the top of the page");
        CHECK(NSMinY(page.frame) == 28, "page moves up by the toolbar's height only");
        CHECK([bookmarks hitTest:NSMakePoint(400, 14)] != nil, "bookmarks still take clicks");

        DPKeepBookmarksBar.on = NO;
        [pane layout];
        CHECK(bookmarks.alphaValue == 0, "bookmarks hide with the toolbar again");
        CHECK(NSMinY(page.frame) == 0, "page fills the pane again");
        CHECK(NSMinY(DPLaidOutFrame(bookmarks)) == 44, "bookmarks keep their laid-out place");

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        [pane layout];
        CHECK([DPToolbarHover forPane:pane] == nil, "hover detached when Hide Toolbar is off");
        CHECK(bar.alphaValue == 1 && bookmarks.alphaValue == 1, "bars visible again");
        CHECK(NSEqualRects(bar.frame, NSMakeRect(0, 0, 800, 44)) && NSEqualRects(bookmarks.frame, NSMakeRect(0, 44, 800, 28))
                  && NSEqualRects(page.frame, NSMakeRect(0, 72, 800, 528)),
              "frames restored when Hide Toolbar is off");

        if (failures) return 1;
        puts("PASS: Hide Toolbar overshoot, focus reveal, and Keep Bookmarks Bar");
    }
    return 0;
}
