#import "StdPatch/StdPatch.h"
#import <mach-o/dyld.h>

static NSEvent *(^monitor)(NSEvent *);
static NSString *gAction;
static NSWindow *gModal;
static int gHandled;
static NSUInteger gHandledKeys;

static id capture(id self, SEL cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    NSCAssert(mask == NSEventMaskLeftMouseDown, @"only left mouse-downs");
    return monitor = [handler copy];
}
static NSString *stringForKey(NSUserDefaults *self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"AppleActionOnDoubleClick"]) return gAction;
    return DPCallOriginal(stringForKey, self, key);
}
static NSWindow *modalWindow(NSApplication *self, SEL cmd) { return gModal; }

@interface _TtC6Window14PlatformWindow : NSWindow
@property NSView *stubContent, *stubFrame;
@property NSWindow *openSheet;
@property BOOL useMask;
@property NSWindowStyleMask mask;
@property int zoomFill, zoom, miniaturize;
@end
@implementation _TtC6Window14PlatformWindow
- (NSView *)contentView { return self.stubContent ?: super.contentView; }
- (NSWindowStyleMask)styleMask { return self.useMask ? self.mask : super.styleMask; }
- (NSWindow *)attachedSheet { return self.openSheet; }
- (void)_zoomFill:(id)sender { self.zoomFill++; }
- (void)performZoom:(id)sender { self.zoom++; }
- (void)performMiniaturize:(id)sender { self.miniaturize++; }
- (void)miniaturize:(id)sender { self.miniaturize++; }
@end

@interface _TtC11Preferences25PlatformPreferencesWindow : NSWindow
@end
@implementation _TtC11Preferences25PlatformPreferencesWindow
@end
@interface _TtC5Popup19PlatformPopupWindow : NSWindow
@end
@implementation _TtC5Popup19PlatformPopupWindow
@end

// Dia's own views, with the superclasses 1.58.0 and 1.59.0 give them.
@interface _TtC5ARCUI19WindowDraggableView : NSView
@end
@implementation _TtC5ARCUI19WindowDraggableView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC13NavigationBar17NavigationBarView : _TtC5ARCUI19WindowDraggableView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end
@interface _TtC10TabSidebar17SidebarHeaderView : _TtC5ARCUI19WindowDraggableView
@end
@implementation _TtC10TabSidebar17SidebarHeaderView
@end
@interface _TtC10TabSidebar15SidebarRootView : _TtC5ARCUI19WindowDraggableView
@end
@implementation _TtC10TabSidebar15SidebarRootView
@end
@interface _TtC8TabStrip21TabStripContainerView : _TtC5ARCUI19WindowDraggableView
@end
@implementation _TtC8TabStrip21TabStripContainerView
@end
@interface _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView : NSView
@end
@implementation _TtCC8TabStrip31TabStripContainerViewControllerP33_466228EC43BE4F33691D8E9BB7BFDE208RootView
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC15WindowTreatment24WindowBackgroundBaseView : NSView
@end
@implementation _TtC15WindowTreatment24WindowBackgroundBaseView
@end

@interface _TtC5ARCUI13HoverableView : NSView
@end
@implementation _TtC5ARCUI13HoverableView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC5ARCUI21WindowStandardButtons : _TtC5ARCUI13HoverableView
@end
@implementation _TtC5ARCUI21WindowStandardButtons
@end
@interface _TtC16PinnedExtensions19PinnedExtensionView : _TtC5ARCUI13HoverableView
@end
@implementation _TtC16PinnedExtensions19PinnedExtensionView
@end
@interface _TtC5ARCUI16HoverableControl : NSControl
@end
@implementation _TtC5ARCUI16HoverableControl
@end
@interface _TtC10TabSurface16TabSurfaceButton : _TtC5ARCUI16HoverableControl
@end
@implementation _TtC10TabSurface16TabSurfaceButton
@end
@interface _TtC5TabUI7TabView : NSControl
@end
@implementation _TtC5TabUI7TabView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC5TabUI15TabDockItemView : NSControl
@end
@implementation _TtC5TabUI15TabDockItemView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC13NavigationBar26NavigationBarCapsuleButton : NSButton
@end
@implementation _TtC13NavigationBar26NavigationBarCapsuleButton
@end
@interface _TtC13NavigationBar16AssistantBarView : NSButton
@end
@implementation _TtC13NavigationBar16AssistantBarView
@end
@interface _TtC7TabList14NewTabCellView : NSButton
@end
@implementation _TtC7TabList14NewTabCellView
@end
@interface _TtC10TabSurface29TabDockProfileIndicatorButton : NSButton
@end
@implementation _TtC10TabSurface29TabDockProfileIndicatorButton
@end
@interface _TtC10DiaLibrary17LibraryButtonView : NSView
@end
@implementation _TtC10DiaLibrary17LibraryButtonView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC10TabSurface19DownloadsButtonView : NSView
@end
@implementation _TtC10TabSurface19DownloadsButtonView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView : NSView
@end
@implementation _TtC8TabStripP33_B0CB782161153EFE9133A89C9E1DF5E27DotView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC11BookmarkBar15BookmarkBarView : NSView
@end
@implementation _TtC11BookmarkBar15BookmarkBarView
@end
@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (void)mouseDown:(NSEvent *)event {}
@end
@interface _TtC5ARCUI24SplitViewContentPaneView : NSView
@end
@implementation _TtC5ARCUI24SplitViewContentPaneView
@end
@interface RenderWidgetHostViewCocoa : NSView
@end
@implementation RenderWidgetHostViewCocoa
- (void)mouseDown:(NSEvent *)event {}
@end
@interface Content : NSView
@end
@implementation Content
- (void)mouseDown:(NSEvent *)event {}
@end

@interface Frame : NSView
@end
@implementation Frame
- (BOOL)_handlePossibleDoubleClickWithModifiers:(NSUInteger)keys {
    gHandled++;
    gHandledKeys = keys;
    return YES;
}
@end
@interface WrongFrame : NSView
@end
@implementation WrongFrame
- (BOOL)_handlePossibleDoubleClickWithModifiers:(double)keys {
    gHandled++;
    return YES;
}
@end
@interface BareFrame : NSView
@end
@implementation BareFrame
@end

@interface Click : NSEvent
@property NSWindow *window;
@property NSEventType type;
@property NSInteger clickCount;
@property NSEventModifierFlags modifierFlags;
@property NSPoint locationInWindow;
@end
@implementation Click
@synthesize window = _window, type = _type, clickCount = _clickCount, modifierFlags = _modifierFlags, locationInWindow = _locationInWindow;
@end

#import "Patches/ZoomOnDoubleClick/ZoomOnDoubleClick.m"

static const NSRect DPBounds = {{0, 0}, {800, 600}};
static NSPoint top(CGFloat fromTop) { return NSMakePoint(400, NSHeight(DPBounds) - fromTop); }

static _TtC6Window14PlatformWindow *makeWindow(Class frameClass) {
    _TtC6Window14PlatformWindow *window = [[_TtC6Window14PlatformWindow alloc] initWithContentRect:DPBounds
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    if (!frameClass) return window;
    window.stubFrame = [[frameClass alloc] initWithFrame:DPBounds];
    window.stubContent = [[NSView alloc] initWithFrame:DPBounds];
    [window.stubFrame addSubview:window.stubContent];
    return window;
}

static Click *click(NSWindow *window, NSPoint point) {
    Click *event = [Click new];
    event.window = window; event.type = NSEventTypeLeftMouseDown; event.clickCount = 2; event.locationInWindow = point;
    return event;
}

static int actions(NSWindow *window) {
    _TtC6Window14PlatformWindow *dia = [window isKindOfClass:_TtC6Window14PlatformWindow.class] ? (id)window : nil;
    return dia.zoomFill + dia.zoom + dia.miniaturize + gHandled;
}

static void fires(NSWindow *window, Click *event, NSString *why) {
    int before = actions(window);
    NSCAssert(monitor(event) == nil, @"consumed: %@", why);
    NSCAssert(actions(window) == before + 1, @"one action: %@", why);
}

static void ignores(NSWindow *window, Click *event, NSString *why) {
    int before = actions(window);
    NSCAssert(monitor(event) == event, @"passed on: %@", why);
    NSCAssert(actions(window) == before, @"no action: %@", why);
}

static void interactive(NSView *view, NSString *why) {
    _TtC6Window14PlatformWindow *window = makeWindow(Frame.class);
    view.frame = NSMakeRect(300, 580, 200, 20);
    [window.stubContent addSubview:view];
    ignores(window, click(window, top(3)), why);
    [view removeFromSuperview];
    fires(window, click(window, top(3)), [why stringByAppendingString:@" gone"]);
}

static NSView *make(const char *name) {
    Class cls = objc_getClass(name);
    NSCAssert(cls, @"%s exists", name);
    return [[cls alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
}

// A bar that spans the top of the window with a child in the middle: the bar's empty parts act, the child's don't.
static void inBar(const char *barName, NSView *child, NSString *childName) {
    NSString *why = [NSString stringWithFormat:@"%@ in %s", childName, barName];
    _TtC6Window14PlatformWindow *window = makeWindow(Frame.class);
    NSView *bar = make(barName);
    bar.frame = NSMakeRect(0, 560, 800, 40);
    child.frame = NSMakeRect(300, 0, 200, 40);
    NSView *inner = [[NSView alloc] initWithFrame:NSMakeRect(20, 0, 160, 40)];
    [child addSubview:inner];
    [bar addSubview:child];
    [window.stubContent addSubview:bar];
    for (CGFloat fromTop = 0.5; fromTop <= DPBorderReach; fromTop += 3) {
        CGFloat y = NSHeight(DPBounds) - fromTop;
        fires(window, click(window, NSMakePoint(50, y)), [NSString stringWithFormat:@"%s beside %@, %.1f down", barName, childName, fromTop]);
        ignores(window, click(window, NSMakePoint(310, y)), [why stringByAppendingFormat:@", %.1f down", fromTop]);
        ignores(window, click(window, NSMakePoint(400, y)), [why stringByAppendingFormat:@", on a view inside it, %.1f down", fromTop]);
    }
    ignores(window, click(window, NSMakePoint(50, NSHeight(DPBounds) - 20)), [why stringByAppendingString:@", below the border"]);
}

static void real(void) {
    _TtC6Window14PlatformWindow *window = makeWindow(nil);
    NSView *frame = window.contentView.superview;
    for (NSView *sub in frame.subviews) if (sub != window.contentView) sub.hidden = YES;
    BOOL handler = [frame respondsToSelector:NSSelectorFromString(@"_handlePossibleDoubleClickWithModifiers:")];
    NSString *chosen = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleActionOnDoubleClick"];
    NSPoint point = NSMakePoint(NSWidth(frame.bounds) / 2, NSHeight(frame.bounds) - 3);
    Click *event = click(window, point);
    NSEvent *result = monitor(event);
    int minimised = window.miniaturize, zoomed = window.zoom, filled = window.zoomFill;
    if ([chosen isEqual:@"None"]) NSCAssert(result == event && !minimised && !zoomed && !filled, @"None does nothing");
    else if ([chosen isEqual:@"Minimize"]) NSCAssert(!result && minimised == 1 && !zoomed && !filled, @"Minimize minimises");
    else if ([chosen isEqual:@"Maximize"]) NSCAssert(!result && zoomed == 1 && !minimised && !filled, @"Maximize zooms");
    else if (@available(macOS 15, *)) NSCAssert(!result && zoomed + filled == 1 && !minimised, @"Fill fills, or zooms where AppKit has no fill");
    else NSCAssert(zoomed + filled <= 1 && !minimised, @"Fill is new in macOS 15");
    NSLog(@"%@ (%@): minimise %d, zoom %d, fill %d", chosen, handler ? @"AppKit's handler" : @"fallback", minimised, zoomed, filled);
}

static void spawn(NSString *action) {
    char path[4096];
    uint32_t size = sizeof(path);
    NSCAssert(!_NSGetExecutablePath(path, &size), @"own path");
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@(path)];
    task.arguments = @[ @"--real", @"-AppleActionOnDoubleClick", action ];
    NSError *error;
    NSCAssert([task launchAndReturnError:&error], @"%@", error);
    [task waitUntilExit];
    NSCAssert(task.terminationStatus == 0, @"AppKit follows %@", action);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(object_getClass(NSEvent.class), @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)capture);
        DPInstallZoomOnDoubleClick();
        NSCAssert(monitor, @"installs a click monitor");
        NSCAssert(!DPVerifyZoomOnDoubleClick(&DPZoomOnDoubleClick), @"verifies while off");
        DPZoomOnDoubleClick.on = YES;
        NSCAssert(!DPVerifyZoomOnDoubleClick(&DPZoomOnDoubleClick), @"verifies once installed");
        if (argc > 1 && !strcmp(argv[1], "--real")) {
            real();
            return 0;
        }
        DPHookClass(NSUserDefaults.class, @selector(stringForKey:), (IMP)stringForKey);
        DPHookClass(NSApplication.class, @selector(modalWindow), (IMP)modalWindow);
        DPZoomOnDoubleClick.on = NO;

        _TtC6Window14PlatformWindow *window = makeWindow(Frame.class);
        ignores(window, click(window, top(3)), @"off");
        DPZoomOnDoubleClick.on = YES;
        fires(window, click(window, top(3)), @"on");
        NSCAssert(gHandled == 1 && gHandledKeys == 0, @"AppKit's handler runs once, with no keys");
        NSCAssert(!window.zoom && !window.zoomFill && !window.miniaturize, @"the window isn't zoomed behind AppKit's handler");
        DPZoomOnDoubleClick.on = NO;
        ignores(window, click(window, top(3)), @"off again");
        DPZoomOnDoubleClick.on = YES;

        fires(window, click(window, top(0.5)), @"the very edge");
        fires(window, click(window, top(DPBorderReach)), @"the edge of the reach");
        ignores(window, click(window, top(DPBorderReach + 0.5)), @"just past the reach");
        ignores(window, click(window, top(40)), @"deep in the window");
        ignores(window, click(window, NSMakePoint(400, 700)), @"above the window");
        ignores(window, click(window, NSMakePoint(-3, 597)), @"left of the window");
        ignores(window, click(window, NSMakePoint(900, 597)), @"right of the window");

        for (NSNumber *count in @[ @0, @1, @3, @4 ]) {
            Click *event = click(window, top(3));
            event.clickCount = count.integerValue;
            ignores(window, event, [NSString stringWithFormat:@"click %@", count]);
        }
        for (NSNumber *type in @[ @(NSEventTypeLeftMouseUp), @(NSEventTypeRightMouseDown), @(NSEventTypeOtherMouseDown), @(NSEventTypeLeftMouseDragged), @(NSEventTypeMouseMoved) ]) {
            Click *event = click(window, top(3));
            event.type = (NSEventType)type.integerValue;
            ignores(window, event, [NSString stringWithFormat:@"event type %@", type]);
        }
        for (NSNumber *key in @[ @(NSEventModifierFlagCommand), @(NSEventModifierFlagOption), @(NSEventModifierFlagControl), @(NSEventModifierFlagShift),
                                 @(NSEventModifierFlagCommand | NSEventModifierFlagShift) ]) {
            Click *event = click(window, top(3));
            event.modifierFlags = key.unsignedIntegerValue;
            ignores(window, event, [NSString stringWithFormat:@"keys %@", key]);
        }
        for (NSNumber *key in @[ @(NSEventModifierFlagCapsLock), @(NSEventModifierFlagFunction), @(NSEventModifierFlagNumericPad) ]) {
            Click *event = click(window, top(3));
            event.modifierFlags = key.unsignedIntegerValue;
            fires(window, event, [NSString stringWithFormat:@"lock or fn key %@", key]);
        }

        ignores(nil, click(nil, top(3)), @"no window");
        NSWindow *plain = [[NSWindow alloc] initWithContentRect:DPBounds styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        plain.releasedWhenClosed = NO;
        ignores(plain, click(plain, top(3)), @"another window");
        NSWindow *settings = [[_TtC11Preferences25PlatformPreferencesWindow alloc] initWithContentRect:DPBounds styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        settings.releasedWhenClosed = NO;
        ignores(settings, click(settings, top(3)), @"Settings, which has a title bar");
        NSWindow *little = [[_TtC5Popup19PlatformPopupWindow alloc] initWithContentRect:DPBounds styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        little.releasedWhenClosed = NO;
        ignores(little, click(little, top(3)), @"Little Dia");
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:DPBounds styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        panel.releasedWhenClosed = NO;
        ignores(panel, click(panel, top(3)), @"a panel");

        window.useMask = YES;
        window.mask = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullScreen;
        ignores(window, click(window, top(3)), @"full screen");
        window.mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        ignores(window, click(window, top(3)), @"a window that can't resize");
        window.mask = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
        fires(window, click(window, top(3)), @"full size content");
        window.useMask = NO;
        window.openSheet = panel;
        ignores(window, click(window, top(3)), @"a sheet is open");
        window.openSheet = nil;
        gModal = panel;
        ignores(window, click(window, top(3)), @"a modal window is up");
        gModal = nil;
        fires(window, click(window, top(3)), @"back to normal");

        NSButton *button = [NSButton buttonWithTitle:@"x" target:nil action:nil];
        interactive(button, @"a button");
        NSView *inButton = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        NSButton *holder = [NSButton buttonWithTitle:@"" target:nil action:nil];
        [holder addSubview:inButton];
        interactive(holder, @"a view inside a button");
        interactive([NSTextField labelWithString:@"title"], @"a label");
        interactive([NSTextView new], @"a text view or field editor");
        interactive([NSSegmentedControl segmentedControlWithLabels:@[ @"a", @"b" ] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil], @"a control");

        NSView *label = [NSView new];
        [label addGestureRecognizer:[[NSClickGestureRecognizer alloc] initWithTarget:nil action:nil]];
        _TtC6Window14PlatformWindow *gesture = makeWindow(Frame.class);
        label.frame = NSMakeRect(300, 580, 200, 20);
        [gesture.stubContent addSubview:label];
        fires(gesture, click(gesture, top(3)), @"a plain view with a gesture recognizer");

        // Dia's chrome that reaches the window's top edge and overrides mouseDown: still lets the border through...
        const char *bars[] = { DPDiaToolbar, DPDiaSidebarHeader, DPDiaTabStrip, "_TtC10TabSidebar15SidebarRootView", "_TtC8TabStrip21TabStripContainerView" };
        // ...while what sits on it keeps its clicks: tabs, buttons, the address field, traffic lights, extensions, the page.
        struct { const char *name; NSString *title; } kept[] = {
            { DPDiaTabView, @"a tab" }, { DPDiaPinnedTab, @"a pinned tab" }, { DPDiaCapsuleButton, @"a toolbar button" },
            { DPDiaAddressField, @"the address field" }, { DPDiaTabSurfaceButton, @"the Top Tabs + button" },
            { DPDiaNewTabButton, @"the sidebar + button" }, { "_TtC10TabSurface29TabDockProfileIndicatorButton", @"the profile button" },
            { DPDiaTrafficLights, @"the traffic lights" }, { DPDiaPinnedExtension, @"a pinned extension" },
            { DPDiaLibraryButton, @"the library button" }, { DPDiaDownloadsButton, @"the downloads button" },
            { DPDiaPageIndicatorDot, @"a page dot" }, { DPDiaBookmarksBar, @"the bookmarks bar" },
            { DPDiaContentPane, @"the page" }, { DPDiaSplitPane, @"a split page" }, { DPDiaRenderWidget, @"web content" },
        };
        for (size_t bar = 0; bar < sizeof(bars) / sizeof(*bars); bar++) {
            _TtC6Window14PlatformWindow *alone = makeWindow(Frame.class);
            NSView *empty = make(bars[bar]);
            empty.frame = NSMakeRect(0, 560, 800, 40);
            [alone.stubContent addSubview:empty];
            for (CGFloat fromTop = 0.5; fromTop <= DPBorderReach; fromTop += 3.25)
                fires(alone, click(alone, NSMakePoint(400, NSHeight(DPBounds) - fromTop)), [NSString stringWithFormat:@"%s empty, %.2f down", bars[bar], fromTop]);
            ignores(alone, click(alone, NSMakePoint(400, NSHeight(DPBounds) - DPBorderReach - 3)), @"below the border");
            for (size_t item = 0; item < sizeof(kept) / sizeof(*kept); item++) inBar(bars[bar], make(kept[item].name), kept[item].title);
        }

        _TtC6Window14PlatformWindow *page = makeWindow(Frame.class);
        NSView *pane = make(DPDiaContentPane), *widget = make(DPDiaRenderWidget);
        pane.frame = DPBounds;
        widget.frame = DPBounds;
        [pane addSubview:widget];
        [page.stubContent addSubview:pane];
        ignores(page, click(page, top(3)), @"a page that fills the window");
        [pane removeFromSuperview];
        fires(page, click(page, top(3)), @"the page is gone");

        _TtC6Window14PlatformWindow *background = makeWindow(Frame.class);
        NSView *tile = make(DPDiaWindowBackgroundTile);
        tile.frame = DPBounds;
        [background.stubContent addSubview:tile];
        fires(background, click(background, top(3)), @"the window background");

        NSView *quiet = [NSView new], *deep = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        [quiet addSubview:deep];
        quiet.frame = NSMakeRect(300, 580, 200, 20);
        [window.stubContent addSubview:quiet];
        fires(window, click(window, top(3)), @"plain views behind the click");
        [quiet removeFromSuperview];

        Content *content = [[Content alloc] initWithFrame:DPBounds];
        window.stubContent = content;
        [window.stubFrame addSubview:content];
        fires(window, click(window, top(3)), @"the content view's own mouse-down doesn't count");

        for (NSArray *row in @[ @[ @"Minimize", @1, @0 ], @[ @"Maximize", @0, @1 ], @[ @"Fill", @0, @1 ], @[ @"Bogus", @0, @1 ] ]) {
            for (Class frameClass in @[ WrongFrame.class, BareFrame.class ]) {
                _TtC6Window14PlatformWindow *fallback = makeWindow(frameClass);
                gAction = row[0];
                gHandled = 0;
                fires(fallback, click(fallback, top(3)), [NSString stringWithFormat:@"%@ on %@", row[0], frameClass]);
                NSCAssert(fallback.miniaturize == [row[1] intValue] && fallback.zoom == [row[2] intValue] && !gHandled, @"%@ falls back to the window", row[0]);
            }
        }
        _TtC6Window14PlatformWindow *bare = makeWindow(BareFrame.class);
        gAction = nil;
        fires(bare, click(bare, top(3)), @"no setting at all");
        NSCAssert(bare.zoom == 1 && !bare.miniaturize, @"no setting zooms");
        for (Class frameClass in @[ Frame.class, WrongFrame.class, BareFrame.class ]) {
            _TtC6Window14PlatformWindow *none = makeWindow(frameClass);
            gAction = @"None";
            gHandled = 0;
            ignores(none, click(none, top(3)), @"None leaves the click alone");
        }
        gAction = nil;

        for (NSString *action in @[ @"Fill", @"Maximize", @"Minimize", @"None" ]) spawn(action);
    }
    return 0;
}
