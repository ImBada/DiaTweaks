#import "Patches/SidebarAddressBar/NativeControls.h"
#import "Patches/SidebarAddressBar/Layout.m"
DPPatch DPSidebarAddressBar;
@interface FlippedHost : NSView @end
@implementation FlippedHost
- (BOOL)isFlipped { return YES; }
@end
@interface SidebarLayoutWindow : NSWindow @end
@implementation SidebarLayoutWindow
- (BOOL)isVisible { return YES; }
@end
@interface NavigationFixtureButton : NSView @end
@implementation NavigationFixtureButton @end
@interface TestTab : NSObject
@property(copy) NSString *URL;
@property(copy) NSString *title;
@end
@implementation TestTab @end
@interface TestScriptWindow : NSObject
@property(copy) NSString *windowId;
@property TestTab *activeTab;
@end
@implementation TestScriptWindow @end
@interface TestDelegate : NSObject <NSApplicationDelegate>
@property NSArray *appleScriptWindows;
@end
@implementation TestDelegate @end
@interface NativeAddressFixture : NSView
@property NSMenu *fixture;
@end
@implementation NativeAddressFixture
- (NSMenu *)menuForEvent:(NSEvent *)event { return self.fixture; }
@end
@interface NonCopyableItem : NSMenuItem @end
@implementation NonCopyableItem
- (id)copyWithZone:(NSZone *)zone { [NSException raise:@"NativeMenuMustNotBeCopied" format:@"native menu item"]; return nil; }
@end
static NSMutableArray<NSEvent *> *PostedShortcuts;
static void CapturePostedShortcut(NSApplication *app, SEL _cmd, NSEvent *event, BOOL atStart) {
    if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp)
        [PostedShortcuts addObject:event];
    else DPCallOriginal(CapturePostedShortcut, app, event, atStart);
}
@interface AddressCommandWindow : NSWindow
@property NSMutableArray<NSEvent *> *received;
@end
@implementation AddressCommandWindow
- (void)sendEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp) { [super sendEvent:event]; return; }
    if (!self.received) self.received = [NSMutableArray new];
    [self.received addObject:event];
}
@end
@interface GridFixtureCollection : NSCollectionView @end
@implementation GridFixtureCollection
- (NSInteger)numberOfSections { return 1; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return 4; }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSView *root = [[FlippedHost alloc] initWithFrame:NSMakeRect(0,0,240,800)];
    Class headerClass = objc_allocateClassPair(NSView.class, DPDiaSidebarHeader, 0);
    objc_registerClassPair(headerClass);
    NSView *header = [[headerClass alloc] initWithFrame:NSMakeRect(0,0,240,54)];
    NSView *body = [[NSView alloc] initWithFrame:NSMakeRect(0,54,240,700)];
    Class footerClass = objc_allocateClassPair(NSView.class, DPDiaSidebarFooter, 0);
    objc_registerClassPair(footerClass);
    NSView *footer = [[footerClass alloc] initWithFrame:NSMakeRect(0,754,240,46)];
    [root addSubview:header]; [root addSubview:body]; [root addSubview:footer];
    DPSidebarAddressBar.on = YES;
    DPPlaceSidebarRow(header);
    DPSidebarAddressRow *row = DPGet(header, &DPRowKey);
    NSCAssert(row.superview == root, @"row must attach above tabs");
    NSCAssert(!NSIntersectsRect(row.frame,body.frame), @"row must not overlap tab host");
    NSCAssert([NSStringFromClass(row.subviews.firstObject.class) isEqual:@"DPSidebarActionButton"], @"address must forward native right-click events");
    [footer removeFromSuperview];
    DPPlaceSidebarRow(header);
    NSCAssert(!row.superview && DPSidebarAddressBar.on, @"horizontal tabs suspend the row without changing preferences");
    [root addSubview:footer];
    DPPlaceSidebarRow(header);
    NSCAssert(row.superview == root, @"returning to vertical tabs restores the row");
    NSScrollView *tabScroll = [[NSScrollView alloc] initWithFrame:body.bounds];
    [body addSubview:tabScroll];
    for (int i = 0; i < 3; i++) {
        header.hidden = YES;
        DPPlaceSidebarRow(header);
        NSCAssert(!row.superview, @"hiding the sidebar should detach its address row");
        body.frame = NSMakeRect(4,60,232,694);
        header.hidden = NO;
        DPPlaceSidebarRow(header);
        NSCAssert(row.superview == root && !NSIntersectsRect(row.frame, body.frame),
                  @"revealing an inset tab host should restore the address row without overlap");
    }
    // Dia can unhide the sidebar root before unhiding its floating parent.
    // Keep the same row and offset through that gap, without a timer tick.
    NSWindow *layoutWindow = [[SidebarLayoutWindow alloc] initWithContentRect:root.bounds
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    NSView *floating = [[NSView alloc] initWithFrame:root.bounds];
    layoutWindow.contentView = floating;
    [floating addSubview:root];
    NSRect revealFrame = body.frame;
    for (NSUInteger cycle = 0; cycle < 3; cycle++) {
        floating.hidden = YES;
        root.hidden = YES;
        DPSidebarRefreshLayout();
        NSCAssert(row.superview == root && NSEqualRects(body.frame, revealFrame),
                  @"a hidden ancestor must not tear down the row or its spacing");
        root.hidden = NO;
        DPPlaceSidebarRow(header);
        NSCAssert(row.superview == root && NSEqualRects(body.frame, revealFrame),
                  @"layout must survive the root unhide while its parent is still hidden");
        floating.hidden = NO;
        NSCAssert(DPSidebarAddressRowAvailable(layoutWindow) && NSEqualRects(body.frame, revealFrame),
                  @"the address row and tab spacing must be ready on the first visible frame");
    }
    [root removeFromSuperview];
    layoutWindow = nil;
    DPAddressNativeControls *owned = DPAddressControlsFor(row, YES);
    owned.scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(6,96,228,90)];
    [root addSubview:owned.scroll positioned:NSWindowBelow relativeTo:body];
    DPPlaceSidebarRow(header);
    NSCAssert(DPGet(header, &DPBodyKey) == body, @"extension tile scroll view must never become the native tab host");
    [owned.scroll removeFromSuperview]; owned.scroll = nil;
    [tabScroll removeFromSuperview];
    body.frame = NSMakeRect(0,54,240,700);
    DPPlaceSidebarRow(header);
    NSRect shifted = body.frame;
    for(int i=0;i<20;i++) DPPlaceSidebarRow(header);
    NSCAssert(NSEqualRects(body.frame,shifted), @"repeated layouts must not shrink tabs");
    root.frame = NSMakeRect(0,0,180,800);
    body.frame = NSMakeRect(0,54,180,700);
    DPPlaceSidebarRow(header);
    NSCAssert(NSWidth(row.frame)==168, @"row must follow sidebar resize");
    DPSidebarComfortableSpacing.on = YES;
    DPPlaceSidebarRow(header);
    NSCAssert(NSMinX(row.frame) == 8 && NSMinX(body.frame) == 2, @"comfortable spacing adds side margins");
    Class pinClass = objc_allocateClassPair(NSView.class, DPDiaPinnedTab, 0);
    objc_registerClassPair(pinClass);
    DPSidebarComfortableSpacing.install();
    NSView *pin = [[pinClass alloc] initWithFrame:NSMakeRect(6,100,70,41)];
    [root addSubview:pin];
    pin.frame = NSMakeRect(6,100,70,41);
    NSCAssert(NSEqualRects(pin.frame,NSMakeRect(7,101,68,39)), @"comfortable pinned tabs need extra gaps");
    for (int i=0;i<20;i++) pin.frame = pin.frame;
    NSCAssert(NSEqualRects(pin.frame,NSMakeRect(7,101,68,39)), @"pinned tabs must not shrink on repeated layouts");
    DPSidebarComfortableSpacing.on = NO;
    pin.frame = pin.frame;
    NSCAssert(NSEqualRects(pin.frame,NSMakeRect(6,100,70,41)), @"switching spacing off restores pinned geometry");
    DPSidebarAddressBar.on = NO;
    DPPlaceSidebarRow(header);
    NSCAssert(!row.superview, @"off must remove row");
    NSCAssert(NSEqualRects(body.frame,NSMakeRect(0,54,180,700)), @"off must restore native content frame");
    NSCAssert([DPSidebarDomain(@"https://user:secret@www.example.com/path?token=private#fragment") isEqual:@"example.com"], @"display only the clean host");
    NSCAssert([DPSidebarDomain(@"about:blank") isEqual:@"Search or enter URL"], @"empty tabs need a prompt");
    NSCAssert([DPSidebarDomain(@"file:///private/local.txt") isEqual:@"Local file"], @"file paths should not be displayed");
    NSCAssert([DPSidebarDomain(@"data:text/html,private") isEqual:@"Current page"], @"opaque content should not be displayed");
    AddressCommandWindow *window = [[AddressCommandWindow alloc] initWithContentRect:NSMakeRect(0,0,240,800) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    window.identifier = @"sidebar-fixture";
    window.contentView = root;
    [root addSubview:row];
    TestTab *tab = [TestTab new];
    tab.URL = @"https://example.com/path?query=1#fragment";
    TestScriptWindow *scripted = [TestScriptWindow new];
    scripted.windowId = window.identifier;
    scripted.activeTab = tab;
    TestDelegate *delegate = [TestDelegate new];
    delegate.appleScriptWindows = @[scripted];
    NSApp.delegate = delegate;
    [row refresh];
    NSCAssert([row.URLString isEqual:tab.URL], @"copy source must retain the full URL");
    NSCAssert([((NSButton *)row.subviews.firstObject).title isEqual:@"example.com"], @"display must follow the active tab");
    NSString *ordinaryURL = tab.URL;
    tab.title = @"Friday Brief";
    tab.URL = @"https://template_output.404.example/";
    [row refresh];
    NSCAssert([((NSButton *)row.subviews.firstObject).title isEqual:@"Friday Brief"], @"generated pages use Dia’s tab title");
    NSCAssert([row.URLString isEqual:tab.URL], @"generated titles preserve the actual address");
    tab.title = @"template_output.404.example";
    [row refresh];
    NSCAssert([((NSButton *)row.subviews.firstObject).title isEqual:@"Dia page"], @"unfinished generated pages use a readable fallback");
    tab.title = @"Regular tab title";
    tab.URL = ordinaryURL;
    [row refresh];
    NSCAssert([((NSButton *)row.subviews.firstObject).title isEqual:@"example.com"], @"ordinary pages still use the host");
    NSButton *addressButton = (NSButton *)row.subviews.firstObject;
    NSCAssert([addressButton.contentTintColor isEqual:NSColor.labelColor], @"loaded addresses keep full contrast");
    NSString *loadedURL = tab.URL;
    for (NSString *emptyURL in @[@"about:blank", @"chrome://newtab/"]) {
        tab.URL = emptyURL;
        [row refresh];
        NSCAssert([addressButton.title isEqual:@"Search or enter URL"], @"empty tabs show the search prompt");
        NSCAssert([addressButton.contentTintColor isEqual:NSColor.secondaryLabelColor], @"the prompt uses the secondary label color");
    }
    tab.URL = loadedURL;
    [row refresh];
    NSCAssert([addressButton.contentTintColor isEqual:NSColor.labelColor], @"navigating restores full contrast");
    row.frameSize = NSMakeSize(220,36);
    DPAddressNativeControls *native = DPAddressControlsFor(row, YES);
    DPCreateAddressExtensionsHost(native);
    [row addSubview:native.scroll];
    NSView *toolbar = [NSView new], *pins = [[NSView alloc] initWithFrame:NSMakeRect(0,0,120,42)], *more = [NSView new];
    [toolbar addSubview:pins]; [toolbar addSubview:more];
    native.more = DPAttachAddressNative(more,row,row,NSZeroRect,NO);
    native.extensions = DPAttachAddressNative(pins,row,native.scroll.contentView,pins.frame,YES);
    Class extensionClass = objc_allocateClassPair(NSView.class, "_TtC16PinnedExtensions19PinnedExtensionView", 0);
    objc_registerClassPair(extensionClass);
    DPSidebarLayoutNativeControls(row);
    NSCAssert(native.scroll.hidden, @"an empty pin list uses no inline space");
    for (int i=0;i<4;i++) [pins addSubview:[[extensionClass alloc] initWithFrame:NSMakeRect(i*30,6,28,28)]];
    DPSidebarLayoutNativeControls(row);
    NSCAssert(NSWidth(native.scroll.frame) == 88 && native.scroll.superview == row, @"three whole native pins fit inline by default");
    [row mouseEntered:nil];
    NSCAssert(NSWidth(native.scroll.frame) == 88 && NSMaxX(native.scroll.frame) < NSMinX(more.frame), @"pins remain left of the site menu");
    [row mouseExited:nil];
    DPSidebarExtensionsOnHover.on = YES;
    DPSidebarLayoutNativeControls(row);
    NSCAssert(native.scroll.hidden && more.hidden && NSWidth(native.scroll.frame) == 88, @"hover-only hides address actions while preserving pin slots");
    NSRect addressAtRest = row.subviews.firstObject.frame;
    [row mouseEntered:nil];
    NSCAssert(!native.scroll.hidden && !more.hidden, @"hover reveals pins and the site menu");
    NSCAssert(NSMinX(addressAtRest) == NSMinX(row.subviews.firstObject.frame) && NSWidth(addressAtRest) > NSWidth(row.subviews.firstObject.frame), @"hover reserves action space without moving the address origin");
    [row mouseExited:nil];
    DPSidebarExtensionsOnHover.on = NO;
    NSMenu *menuBar = [NSMenu new];
    NSMenuItem *extensionsMenu = [[NSMenuItem alloc] initWithTitle:@"Extensions" action:nil keyEquivalent:@""];
    extensionsMenu.submenu = [[NSMenu alloc] initWithTitle:@"Extensions"];
    [menuBar addItem:extensionsMenu];
    NSApp.mainMenu = menuBar;
    [row addSubview:native.extensionsButton];
    DPSidebarExtensionTiles.on = YES;
    DPSidebarExtensionsMenuOnly.on = YES;
    DPSidebarLayoutNativeControls(row);
    NSCAssert(!native.extensionsButton.hidden && native.scroll.hidden && !native.gridHeight, @"menu only overrides every pin display");
    DPSidebarExtensionsMenuOnly.on = NO;
    DPSidebarExtensionTiles.on = NO;
    DPSidebarLayoutNativeControls(row);
    NSCAssert(native.extensionsButton.hidden && !native.scroll.hidden, @"disabling menu only restores pin display");
    GridFixtureCollection *collection = [[GridFixtureCollection alloc] initWithFrame:NSMakeRect(0,0,120,42)];
    NSCollectionViewLayout *originalLayout = [NSCollectionViewFlowLayout new];
    collection.collectionViewLayout = originalLayout;
    [pins addSubview:collection];
    DPSidebarExtensionTiles.on = YES;
    DPSidebarExtensionsOnHover.on = YES;
    DPSidebarLayoutNativeControls(row);
    DPSidebarExtensionDivider.on = YES;
    DPSidebarLayoutNativeControls(row);
    NSCAssert(native.gridDivider.superview == root && NSMinY(native.gridDivider.frame) > NSMaxY(native.scroll.frame), @"divider follows the grid");
    NSCAssert(!native.scroll.hidden, @"grid stays visible with inline hover reveal enabled");
    DPSidebarExtensionsOnHover.on = NO;
    NSCAssert(native.gridHeight == 59 && native.scroll.superview == root && NSMinY(native.scroll.frame) > NSMaxY(row.frame),
              @"grid mode reserves two rows below the address bar");
    NSCollectionViewLayoutAttributes *last = [collection.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:3 inSection:0]];
    NSCAssert(NSMinY(last.frame) == 32, @"the fourth native item must wrap into the second tile row");
    DPSidebarExtensionTiles.on = NO;
    DPSidebarLayoutNativeControls(row);
    NSCAssert(!native.gridDivider.superview && !native.gridHeight && native.scroll.superview == row && collection.collectionViewLayout == originalLayout,
              @"turning tiles off restores the original native layout and inline slot");
    DPSidebarRestoreNativeControls(row);
    DPSidebarAddressBar.on = YES;
    Class toolbarClass = objc_allocateClassPair(NSView.class, DPDiaToolbar, 0); objc_registerClassPair(toolbarClass);
    Class pinsClass = objc_allocateClassPair(NSView.class, "_TtC16PinnedExtensions20PinnedExtensionsView", 0); objc_registerClassPair(pinsClass);
    NSView *oldToolbar = [[toolbarClass alloc] initWithFrame:NSMakeRect(0,0,300,42)];
    NSView *oldPins = [[pinsClass alloc] initWithFrame:NSMakeRect(0,0,60,42)];
    [root addSubview:oldToolbar]; [oldToolbar addSubview:oldPins];
    DPSidebarRefreshNativeControls(row);
    DPAddressNativeSlot *mountedPins = native.extensions;
    oldToolbar.hidden = YES;
    for (NSUInteger i=0;i<10;i++) DPSidebarRefreshNativeControls(row);
    NSCAssert(native.extensions == mountedPins && oldPins.superview == native.scroll.contentView, @"a temporary missing toolbar must not detach mounted pins");
    NSView *newToolbar = [[toolbarClass alloc] initWithFrame:NSMakeRect(0,0,300,42)]; [root addSubview:newToolbar];
    for (NSUInteger i=0;i<10;i++) DPSidebarRefreshNativeControls(row);
    NSCAssert(native.extensions == mountedPins, @"an incomplete replacement toolbar must keep the current pins mounted");
    NSView *newPins = [[pinsClass alloc] initWithFrame:NSMakeRect(0,0,60,42)]; [newToolbar addSubview:newPins];
    DPSidebarRefreshNativeControls(row);
    NSCAssert(native.extensions.view == newPins && oldPins.superview == oldToolbar, @"a ready replacement transfers ownership once and restores the old host");
    Class currentFieldClass = objc_allocateClassPair(NativeAddressFixture.class, DPDiaAddressField, 0); objc_registerClassPair(currentFieldClass);
    NSView *currentField = [[currentFieldClass alloc] initWithFrame:NSMakeRect(0,0,200,30)];
    NSTextView *liveURL = [[NSTextView alloc] initWithFrame:currentField.bounds];
    [currentField addSubview:liveURL]; [newToolbar addSubview:currentField];
    NSString *beforePathTest = tab.URL; tab.URL = @"https://example.com/pinned";
    liveURL.string = @"example.com/next?query=2#anchor";
    NSCAssert([DPSidebarURL(window) isEqual:@"https://example.com/next?query=2#anchor"], @"pinned tabs must expose the current path, query and fragment");
    liveURL.string = @"Copied current URL";
    NSCAssert([DPSidebarURL(window) isEqual:tab.URL], @"copy confirmation text must never become a URL");
    liveURL.string = @"other.example/path";
    NSCAssert([DPSidebarURL(window) isEqual:tab.URL], @"a different pane's address must not replace the active tab URL");
    liveURL.string = @"example.com/next…";
    NSCAssert([DPSidebarURL(window) isEqual:tab.URL], @"a truncated display address must not become a navigation target");
    tab.URL = beforePathTest;
    DPSidebarRestoreNativeControls(row); [oldToolbar removeFromSuperview]; [newToolbar removeFromSuperview];
    DPSidebarAddressBar.on = NO;
    NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:[row convertPoint:NSMakePoint(20,18) toView:nil] modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSEvent *left = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:rightClick.locationInWindow modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSCAssert(![row menuForEvent:left], @"ordinary clicks from extension menus must not open the address context menu");
    NSMenu *context = [row menuForEvent:rightClick];
    NSCAssert(context.numberOfItems == 2 && [context.itemArray[1].title isEqual:@"Copy Link"], @"unfocused address must have a usable Copy Link action");
    Class nativeClass = objc_getClass(DPDiaAddressField);
    NativeAddressFixture *nativeField = [[nativeClass alloc] initWithFrame:NSMakeRect(0,0,200,30)];
    nativeField.fixture = [NSMenu new];
    [nativeField.fixture addItem:[[NonCopyableItem alloc] initWithTitle:@"Native action" action:nil keyEquivalent:@""]];
    [root addSubview:nativeField];
    context = [row menuForEvent:rightClick];
    NSCAssert(context == nativeField.fixture && context.numberOfItems == 4, @"reuse native items without copying");
    NSCAssert([row menuForEvent:rightClick].numberOfItems == 4, @"repeated right-click must not duplicate address actions");
    [nativeField removeFromSuperview];
    tab.URL = @"about:blank";
    [row refresh];
    NSCAssert([row menuForEvent:rightClick].numberOfItems == 1, @"blank context must retain the editor action");
    DPSidebarInstallContextTracking();
    NSMenu *extensionContext = [NSMenu new];
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications postNotificationName:NSMenuDidBeginTrackingNotification object:extensionContext];
    NSCAssert(![row menuForEvent:rightClick], @"tracking an extension menu blocks a replayed sidebar context event");
    [notifications postNotificationName:NSMenuDidEndTrackingNotification object:extensionContext];
    NSCAssert(![row menuForEvent:rightClick], @"dismissal must not reopen the sidebar menu with the old right click");
    NSEvent *fresh = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:rightClick.locationInWindow modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                                        context:nil eventNumber:2 clickCount:1 pressure:1];
    NSCAssert([row menuForEvent:fresh], @"a fresh right click still opens the address menu");
    NSMenu *bar = [NSMenu new];
    bar.autoenablesItems = NO;
    for (NSString *key in @[@"l", @"t"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key action:@selector(openEditor:) keyEquivalent:key];
        item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        item.target = row;
        [bar addItem:item];
    }
    NSApp.mainMenu = bar;
    PostedShortcuts = [NSMutableArray new];
    DPHookClass(NSApp.class, @selector(postEvent:atStart:), (IMP)CapturePostedShortcut);
    tab.URL = @"https://example.com/";
    NSCAssert(DPSidebarOpenEditor(row), @"loaded address should dispatch editor shortcut");
    NSCAssert(window.received.count == 0, @"never dispatch a synthetic shortcut directly to the window");
    for (NSString *key in @[@"l", @"t"]) {
        if ([key isEqual:@"t"]) {
            tab.URL = @"about:blank";
            NSCAssert(DPSidebarOpenEditor(row), @"blank page should dispatch new-tab shortcut");
        }
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        NSCAssert(PostedShortcuts.count == 2, @"queue a complete key press");
        NSEvent *down = PostedShortcuts[0], *up = PostedShortcuts[1];
        NSCAssert(down.type == NSEventTypeKeyDown && up.type == NSEventTypeKeyUp &&
            [down.characters isEqual:key] && down.windowNumber == window.windowNumber,
            @"queue the native shortcut for the owning window");
        [PostedShortcuts removeAllObjects];
    }
    [window orderOut:nil];
    NSApp.delegate = nil;
    puts("PASS: no overlap, no layout drift, resize, toggle restoration, URL display privacy, active-tab refresh, non-copyable native menus, and window-targeted editor/new-tab shortcuts");
} }
