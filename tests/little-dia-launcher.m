#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "Patches/LittleDia/LittleDia.h"
#import "runloop.h"

DPPatch DPLittleDia, DPLittleDiaTabLinks, DPLittleDiaFollowRules, DPLittleDiaRemember;

static NSMutableArray<NSURL *> *gOpened;
static int gBlankOpened;
static void (^gNewWindowAction)(void);
static id gBrowser;

NSURL *DPAddressURL(NSString *typed) {
    NSString *text = [typed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) return nil;
    return [text containsString:@"."] ? [NSURL URLWithString:[@"https://" stringByAppendingString:text]] : nil;
}

void DPOpenLinkInLittleDia(NSURL *url) { [gOpened addObject:url]; }
void DPOpenBlankLittleDia(void) { gBlankOpened++; }
id DPCommandBrowser(void) { return gBrowser; }
id DPMsg(id object, SEL sel) { return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil; }
static BOOL gReady = YES;
BOOL DPLittleDiaReady(void) { return gReady; }
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) {
    gNewWindowAction = [action copy];
    return [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
}
void DPOnLaunch(void (^block)(void)) { block(); }

@interface FakeEngine : NSObject
@property (nonatomic, copy) NSString *url;
@end
@implementation FakeEngine
@end

@interface FakePreferences : NSObject
@property (nonatomic, strong) FakeEngine *engine;
@end
@implementation FakePreferences
- (id)getDefaultSearchEngine { return self.engine; }
@end

@interface FakeContext : NSObject
@property (nonatomic, strong) FakePreferences *preferences;
@end
@implementation FakeContext
@end

@interface FakeBrowser : NSObject
@property (nonatomic, strong) FakeContext *context;
@end
@implementation FakeBrowser
@end

#import "Patches/LittleDia/Launcher.m"
#import "Patches/LittleDia/NewWindow.m"
#import "Patches/LittleDia/Profile.m"

BOOL DPIsLittleDiaWindow(NSWindow *window) { return YES; }
id DPLittleDiaPage(NSWindow *window) { return nil; }
NSString *DPLittleDiaProfileName(NSWindow *window) { return @"Personal"; }
BOOL DPSendToLittleDia(NSDictionary *request) { return YES; }
NSDictionary *DPLittleDiaTab(NSWindow *window, NSString *action) { return @{}; }
void DPPromoteLittleDiaWindow(NSWindow *window) {}
void DPLittleDiaGo(NSWindow *window, SEL action) {}
void DPBringBackPutAway(NSWindow *little) {}
NSString *DPLittleDiaURL(NSWindow *window) { return @"https://example.com"; }
NSView *DPMakeAddressView(NSView *title) { return [NSView new]; }
void DPRefreshAddressView(NSView *view) {}
BOOL DPIsKind(id object, const char *className) { return object && [NSStringFromClass([object class]) isEqualToString:@(className)]; }
NSView *DPFindView(NSView *root, BOOL (^match)(NSView *view)) {
    if (!root) return nil;
    if (match(root)) return root;
    for (NSView *sub in root.subviews) {
        NSView *found = DPFindView(sub, match);
        if (found) return found;
    }
    return nil;
}
NSArray<NSView *> *DPFindViews(const char *className) { return @[]; }
BOOL DPHasLabel(NSView *view, NSString *label) { return [view.accessibilityLabel isEqualToString:label]; }
id DPGet(id object, const void *key) { return object ? objc_getAssociatedObject(object, key) : nil; }
void DPSet(id object, const void *key, id value) { if (object) objc_setAssociatedObject(object, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
void DPHook(const char *className, SEL sel, IMP replacement) {}
IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame) { return (IMP)abort; }
void DPPopOriginalIMP(DPHookFrame *frame) {}

#import "Patches/LittleDia/Bar.m"

@interface CountingBarMenuDelegate : NSObject <NSMenuDelegate>
@property NSInteger updates;
@end
@implementation CountingBarMenuDelegate
- (void)menuNeedsUpdate:(NSMenu *)menu { self.updates++; }
@end

@interface FakeBarAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSArray *appleScriptWindows;
@end
@implementation FakeBarAppDelegate
@end

@interface FakeRGBAColor : NSObject
@property float r, g, b, a;
@end
@implementation FakeRGBAColor
@end

@interface FakeColorPage : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) FakeRGBAColor *bg;
@property NSInteger colorReads;
@end
@implementation FakeColorPage
- (id)rootBackgroundColor {
    self.colorReads++;
    return self.bg;
}
@end

static NSMenu *gPoppedBarMenu;
static BOOL DPMenu_captureBarPopUp(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    gPoppedBarMenu = self;
    return YES;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static BOOL gPanelShown;
static BOOL DPPanel_isVisible(id self, SEL _cmd) { return gPanelShown; }
static void DPPanel_makeKeyAndOrderFront(id self, SEL _cmd, id sender) { gPanelShown = YES; }
static void DPPanel_orderOut(id self, SEL _cmd, id sender) { gPanelShown = NO; }
static NSPoint DPEvent_mouseLocation(id self, SEL _cmd) { return NSMakePoint(-100000, -100000); }

static void DPSwapMethod(Class cls, SEL sel, IMP imp) {
    class_replaceMethod(cls, sel, imp, method_getTypeEncoding(class_getInstanceMethod(cls, sel)));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Track the panel's visibility without ever ordering a real window onto the host's desktop or reading its cursor.
        DPSwapMethod(DPLittleDiaLauncherPanel.class, @selector(isVisible), (IMP)DPPanel_isVisible);
        DPSwapMethod(DPLittleDiaLauncherPanel.class, @selector(makeKeyAndOrderFront:), (IMP)DPPanel_makeKeyAndOrderFront);
        DPSwapMethod(DPLittleDiaLauncherPanel.class, @selector(orderOut:), (IMP)DPPanel_orderOut);
        DPSwapMethod(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)DPEvent_mouseLocation);
        gOpened = [NSMutableArray array];
        FakeEngine *engine = [FakeEngine new];
        engine.url = @"https://kagi.com/search?q={searchTerms}";
        FakePreferences *preferences = [FakePreferences new];
        preferences.engine = engine;
        FakeContext *context = [FakeContext new];
        context.preferences = preferences;
        FakeBrowser *browser = [FakeBrowser new];
        browser.context = context;
        gBrowser = browser;

        DPLittleDia.on = YES;
        DPLittleDiaLauncher.on = YES;

        DPToggleLittleDiaLauncher();
        CHECK(DPLittleDiaLauncherVisible(), "the launcher opens");
        CHECK(gBlankOpened == 0, "no blank Little Dia window opens");

        DPLittleDiaLauncherController *controller = [DPLittleDiaLauncherController shared];
        controller.field.stringValue = @"example.com/page";
        [controller control:controller.field textView:[NSTextView new] doCommandBySelector:@selector(insertNewline:)];
        CHECK(!DPLittleDiaLauncherVisible(), "the launcher closes after Return");
        CHECK(gOpened.count == 1 && [gOpened.lastObject.absoluteString isEqual:@"https://example.com/page"], "the URL opens in Little Dia");

        DPToggleLittleDiaLauncher();
        controller.field.stringValue = @"weather tokyo";
        [controller control:controller.field textView:[NSTextView new] doCommandBySelector:@selector(insertNewline:)];
        CHECK(gOpened.count == 2 && [gOpened.lastObject.absoluteString isEqual:@"https://kagi.com/search?q=weather%20tokyo"],
              "the search query opens on the default engine");

        DPToggleLittleDiaLauncher();
        controller.field.stringValue = @"   ";
        [controller control:controller.field textView:[NSTextView new] doCommandBySelector:@selector(insertNewline:)];
        CHECK(DPLittleDiaLauncherVisible(), "an empty query keeps the launcher open");
        CHECK(gOpened.count == 2, "an empty query opens nothing");
        [controller control:controller.field textView:[NSTextView new] doCommandBySelector:@selector(cancelOperation:)];
        CHECK(controller.resignObserver == nil, "the app-resign observer is removed when the launcher closes");

        DPToggleLittleDiaLauncher();
        controller.field.stringValue = @"example.com";
        [controller control:controller.field textView:[NSTextView new] doCommandBySelector:@selector(cancelOperation:)];
        CHECK(!DPLittleDiaLauncherVisible(), "Escape closes the launcher");
        CHECK(gOpened.count == 2, "Escape opens nothing");

        DPToggleLittleDiaLauncher();
        [controller windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:controller.panel]];
        CHECK(!DPLittleDiaLauncherVisible(), "resigning key closes the launcher");

        DPToggleLittleDiaLauncher();
        CHECK(DPLittleDiaLauncherVisible(), "the launcher reopens");
        DPToggleLittleDiaLauncher();
        CHECK(!DPLittleDiaLauncherVisible(), "pressing ⌥⌘N again closes the launcher");

        DPToggleLittleDiaLauncher();
        DPLittleDiaLauncher.on = NO;
        DPLittleDiaLauncher.apply(&DPLittleDiaLauncher);
        CHECK(!DPLittleDiaLauncherVisible(), "turning the tweak off closes the launcher");

        DPLittleDiaLauncher.on = NO;
        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        fileRoot.submenu = [[NSMenu alloc] initWithTitle:@"File"];
        [mainMenu addItem:fileRoot];
        NSApp.mainMenu = mainMenu;
        DPInstallLittleDiaNewWindow();
        DPRefreshLittleDiaNewWindow();
        CHECK(gNewWindowAction != nil, "the File menu item has an action");
        gNewWindowAction();
        CHECK(gBlankOpened == 1, "with the launcher off, ⌥⌘N opens a blank Little Dia window");

        DPLittleDiaLauncher.on = YES;
        gNewWindowAction();
        CHECK(DPLittleDiaLauncherVisible(), "with the launcher on, ⌥⌘N shows the launcher");
        CHECK(gBlankOpened == 1, "no extra blank window opens");

        DPLittleDia.on = NO;
        DPLittleDiaLauncher.apply(&DPLittleDiaLauncher);
        CHECK(!DPLittleDiaLauncherVisible(), "turning Little Dia off closes the launcher");
        DPLittleDia.on = YES;

        DPLittleDia.on = YES;
        gReady = NO;
        gLooks = 500;
        DPRefreshLittleDiaNewWindow();
        CHECK([DPFileMenu() indexOfItem:gItem] < 0, "the File menu leaves the item out while the extension isn't ready");
        DPLittleDia.on = NO;
        DPRefreshLittleDiaNewWindow();
        DPLittleDia.on = YES;
        DPRefreshLittleDiaNewWindow();
        gReady = YES;
        DPPumpUntil(^BOOL { return [DPFileMenu() indexOfItem:gItem] >= 0; });
        CHECK([DPFileMenu() indexOfItem:gItem] >= 0, "turning Little Dia back on shows New Little Dia Window once the poll sees the extension ready");

        DPSwapMethod(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPMenu_captureBarPopUp);
        NSArray<NSString *> *names = @[ @"Personal", @"Work", @"Study", @"Travel" ];
        NSMutableArray *scriptProfiles = [NSMutableArray array];
        for (NSString *n in names) [scriptProfiles addObject:@{ @"name" : n }];
        FakeBarAppDelegate *appDel = [FakeBarAppDelegate new];
        appDel.appleScriptWindows = @[ @{ @"windowId" : @"w1", @"appleScriptProfiles" : scriptProfiles } ];
        NSApp.delegate = appDel;

        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        NSMenu *moveMenu = [[NSMenu alloc] initWithTitle:@"Move to Profile"];
        for (NSString *n in names) {
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:n action:nil keyEquivalent:@""];
            it.image = img;
            [moveMenu addItem:it];
        }
        CountingBarMenuDelegate *moveDel = [CountingBarMenuDelegate new];
        moveMenu.delegate = moveDel;

        NSMenu *tabsMenu = [[NSMenu alloc] initWithTitle:@"Tabs"];
        NSMenuItem *moveRoot = [[NSMenuItem alloc] initWithTitle:@"Move to Profile" action:nil keyEquivalent:@""];
        moveRoot.submenu = moveMenu;
        [tabsMenu addItem:moveRoot];
        CountingBarMenuDelegate *tabsDel = [CountingBarMenuDelegate new];
        tabsMenu.delegate = tabsDel;
        NSMenuItem *tabsRoot = [[NSMenuItem alloc] initWithTitle:@"Tabs" action:nil keyEquivalent:@""];
        tabsRoot.submenu = tabsMenu;
        [mainMenu addItem:tabsRoot];

        NSButton *profBtn = DPMakeProfilesButton();
        DPShowProfiles(profBtn);
        CHECK(tabsDel.updates == 1 && moveDel.updates == 1, "DPShowProfiles updates Tabs and Move to Profile menus once total, not once per profile");
        CHECK(gPoppedBarMenu.numberOfItems == 4 && gPoppedBarMenu.itemArray[0].image == img && gPoppedBarMenu.itemArray[3].image == img,
              "DPShowProfiles attaches every profile image from the hoisted submenu");

        NSView *barRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
        NSView *titleView = [[NSView alloc] initWithFrame:NSMakeRect(80, 6, 200, 28)];
        [barRow addSubview:titleView];
        DPLittleBar *bar = DPMakeBar(titleView);
        CHECK(fabs(bar.timer.timeInterval - 1.0) < 0.001, "DPMakeBar schedules its safety timer at 1.0 s, not 0.25 s");
        [bar.timer invalidate];

        FakeRGBAColor *dark = [FakeRGBAColor new];
        dark.r = 0.1f; dark.g = 0.1f; dark.b = 0.15f; dark.a = 1.0f;
        FakeColorPage *page = [FakeColorPage new];
        page.url = [NSURL URLWithString:@"https://example.com/one"];
        page.bg = dark;
        DPMatchPage(barRow, page);
        CHECK(page.colorReads == 1 && barRow.layer.backgroundColor != NULL, "first DPMatchPage samples page color and tints bar");
        DPMatchPage(barRow, page);
        DPMatchPage(barRow, page);
        CHECK(page.colorReads == 1, "repeated DPMatchPage with unchanged URL skips DPPageColor Chromium calls");
        page.url = [NSURL URLWithString:@"https://example.com/two"];
        DPMatchPage(barRow, page);
        CHECK(page.colorReads == 2, "changing page URL re-samples DPPageColor");
        DPMatchPage(barRow, nil);
        CHECK(barRow.layer.backgroundColor == NULL && barRow.appearance == nil, "DPMatchPage(row, nil) clears bar tint and appearance");

        if (failures) return 1;
        puts("PASS: Little Dia launcher opens, resolves URLs and searches, and dismisses cleanly");
    }
    return 0;
}
