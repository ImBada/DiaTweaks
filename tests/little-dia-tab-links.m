#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "StdPatch/StdPatch.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"

DPPatch DPLittleDia;

static NSEventModifierFlags gModifiers;
static NSEventModifierFlags DPEvent_modifierFlags(NSEvent *self, SEL _cmd) { return gModifiers; }

static NSString *gChoice = @"all";
static NSWindow *gWindow;
static id gBrowser;
static int gOpened;
static NSURL *gOpenedURL;
static NSWindow *gOpenedFrom;

NSString *DPChoice(DPPatch *patch) { return gChoice; }
void DPOnLaunch(void (^block)(void)) { block(); }
BOOL DPLittleDiaReady(void) { return YES; }
BOOL DPIsLittleDiaWindow(NSWindow *window) { return NO; }
id DPLittleDiaPage(NSWindow *window) { return nil; }
id DPCommandBrowser(void) { return gBrowser; }
id DPBrowserOfContents(id contents) { return gBrowser; }
NSWindow *DPBrowserWindow(id browser) { return gWindow; }
NSString *DPDomainKey(NSString *url) { return url ? [NSURL URLWithString:url].host : nil; }
NSString *DPRegistrableDomain(NSString *host) {
    NSArray *parts = [host componentsSeparatedByString:@"."];
    NSUInteger keep = MIN(parts.count, 2);
    return [[parts subarrayWithRange:NSMakeRange(parts.count - keep, keep)] componentsJoinedByString:@"."];
}
id DPMsg(id object, SEL sel) { return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil; }
BOOL DPMsgBool(id object, SEL sel) { return [object respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(object, sel); }
NSString *DPText(id value) { return [value isKindOfClass:NSString.class] ? value : [value description]; }
void DPOpenTabLinkInLittleDia(NSURL *url, NSWindow *source) {
    gOpened++;
    gOpenedURL = url;
    gOpenedFrom = source;
}

@interface DPFakeContextID : NSObject
- (BOOL)isIncognito;
@end
@implementation DPFakeContextID
- (BOOL)isIncognito { return NO; }
@end

@interface DPFakeContext : NSObject
@property (strong) DPFakeContextID *id;
@end
@implementation DPFakeContext
@end

@interface DPFakeBrowser : NSObject
@property (strong) DPFakeContext *context;
@end
@implementation DPFakeBrowser
@end

@interface DPFakeTabState : NSObject
@property (nonatomic, copy) NSString *text;
@end
@implementation DPFakeTabState
- (NSString *)description { return self.text; }
- (id)safeSwiftValueForKey:(NSString *)key { return nil; }
@end

@interface DPFakeState : NSObject
@property (nonatomic, strong) DPFakeTabState *currentValue;
@end
@implementation DPFakeState
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"currentValue"] ? self.currentValue : nil; }
@end

@interface DPFakeViewModel : NSObject
@property (nonatomic, strong) DPFakeState *stateSubject;
@end
@implementation DPFakeViewModel
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"stateSubject"] ? self.stateSubject : nil; }
@end

@interface _TtC5TabUI7TabView : NSView
@property (nonatomic, strong) DPFakeViewModel *viewModel;
@end
@implementation _TtC5TabUI7TabView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"viewModel"] ? self.viewModel : nil; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    [menu addItemWithTitle:@"Unpin" action:@selector(description) keyEquivalent:@""].target = self;
    return menu;
}
@end

@interface DPFakePage : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSURL *url;
@end
@implementation DPFakePage
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"identifier"] ? self.identifier : nil; }
@end

@interface DPFakeAction : NSObject
@property (nonatomic, copy) NSURL *url;
@property NSInteger navigationDisposition, navigationType;
@end
@implementation DPFakeAction
@end

@interface DPPeekCard : NSView
@property (nonatomic, weak) id page;
@end
@implementation DPPeekCard
@end

static NSInteger gOriginalPolicy, gStayingPolicy = DPCurrentTab;
static int gOriginalCalls;

@interface _TtC3ADK18WebContentChromium : NSObject
- (NSInteger)webContents:(id)webContents decidePolicyForNavigationAction:(id)action;
- (void)webContents:(id)webContents didChangeStatusText:(NSString *)text;
@end
@implementation _TtC3ADK18WebContentChromium
- (NSInteger)webContents:(id)webContents decidePolicyForNavigationAction:(id)action {
    gOriginalCalls++;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(action, @selector(navigationDisposition)) == DPCurrentTab ? gStayingPolicy : gOriginalPolicy;
}
- (void)webContents:(id)webContents didChangeStatusText:(NSString *)text {}
@end

@interface DPVisibleWindow : NSWindow
@end
@implementation DPVisibleWindow
- (BOOL)isVisible { return YES; }
@end

#import "Patches/LittleDia/TabLinks.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void PumpFor(NSTimeInterval seconds) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static DPFakePage *DPMakePage(NSString *identifier, NSString *url) {
    DPFakePage *page = [DPFakePage new];
    page.identifier = identifier;
    page.url = [NSURL URLWithString:url];
    return page;
}

static DPFakeAction *DPMakeAction(NSString *url, NSInteger disposition, NSInteger type) {
    DPFakeAction *action = [DPFakeAction new];
    action.url = [NSURL URLWithString:url];
    action.navigationDisposition = disposition;
    action.navigationType = type;
    return action;
}

static _TtC3ADK18WebContentChromium *gDelegate;

static NSInteger DPDecide(DPFakePage *page, DPFakeAction *action, NSInteger original) {
    gOriginalPolicy = original;
    return [gDelegate webContents:page decidePolicyForNavigationAction:action];
}

static void DPHover(DPFakePage *page, NSString *text) { [gDelegate webContents:page didChangeStatusText:text]; }

static void DPMouseDown(void) {
    [NSApp sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0
                                       timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1]];
}

static void DPSettle(void) {
    PumpFor(0.05);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(object_getClass(NSEvent.class), @selector(modifierFlags), (IMP)DPEvent_modifierFlags);
        gWindow = [[DPVisibleWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300) styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered defer:NO];
        DPFakeBrowser *browser = [DPFakeBrowser new];
        browser.context = [DPFakeContext new];
        browser.context.id = [DPFakeContextID new];
        gBrowser = browser;
        gDelegate = [_TtC3ADK18WebContentChromium new];

        DPLittleDia.on = YES;
        DPLittleDiaTabLinks.on = YES;
        DPLittleDiaTabLinks.install();

        DPFakePage *page = DPMakePage(@"11111111-1111-1111-1111-111111111111", @"https://one.example/");
        NSString *target = @"https://other.example/article";
        CHECK(!DPLittleDiaTabLinks.verify(&DPLittleDiaTabLinks), "both hooks land on Dia's web contents delegate");

        DPLittleDia.on = NO;
        DPLittleDiaTabLinks.on = YES;
        DPHover(page, target);
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "Little Dia off leaves the link to Dia");
        DPSettle();
        CHECK(gOpened == 0, "Little Dia off opens nothing");

        DPLittleDia.on = YES;
        DPLittleDiaTabLinks.on = NO;
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "Open Links from Tabs off leaves the link to Dia");
        DPSettle();
        CHECK(gOpened == 0, "Open Links from Tabs off opens nothing");
        DPLittleDiaTabLinks.on = YES;

        DPHover(page, target);
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPIgnoreAction, "a hovered new-tab link is taken without Peek installed");
        DPSettle();
        CHECK(gOpened == 1 && [gOpenedURL.absoluteString isEqual:target] && gOpenedFrom == gWindow, "the link opens in Little Dia from the page's own window");

        DPHover(page, nil);
        gOpened = 0;
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "a script-opened tab with no link under the pointer stays a tab");
        DPSettle();
        CHECK(gOpened == 0, "a script-opened tab isn't taken");

        DPHover(page, target);
        DPMouseDown();
        DPHover(page, nil);
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPIgnoreAction, "the link under the pointer at mouse-down still counts after Dia clears the status text");
        DPSettle();
        CHECK(gOpened == 1, "the pressed link opens in Little Dia");

        gOpened = 0;
        DPHover(page, target);
        gModifiers = NSEventModifierFlagShift;
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "a Shift-click keeps its usual meaning");
        gModifiers = NSEventModifierFlagCommand;
        CHECK(DPDecide(page, DPMakeAction(target, DPBackgroundTab, 0), DPBackgroundTab) == DPBackgroundTab, "a ⌘-click keeps its usual meaning");
        gModifiers = 0;
        DPSettle();
        CHECK(gOpened == 0, "modified clicks open nothing");

        CHECK(DPDecide(page, DPMakeAction(target, DPCurrentTab, 0), DPCurrentTab) == DPCurrentTab, "a link that stays in the tab stays");
        DPSettle();
        CHECK(gOpened == 0, "same-tab links open nothing");

        DPPeekCard *card = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        card.page = page;
        [gWindow.contentView addSubview:card];
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "a link clicked inside a Peek card stays in the card");
        DPSettle();
        CHECK(gOpened == 0, "nothing opens from a Peek card");
        [card removeFromSuperview];

        gChoice = @"pinned";
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "pinned-only mode leaves regular tabs alone");
        DPSettle();
        CHECK(gOpened == 0, "a regular tab's link isn't taken in pinned-only mode");

        gStayingPolicy = DPForegroundTab;
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPIgnoreAction, "an icon-only pinned tab's link is taken even in pinned-only mode");
        DPSettle();
        CHECK(gOpened == 1, "an icon-only pinned tab's link opens in Little Dia");
        gStayingPolicy = DPCurrentTab;
        gOpened = 0;

        PumpFor(0.6);
        _TtC5TabUI7TabView *row = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 30)];
        DPFakeTabState *state = [DPFakeTabState new];
        state.text = [NSString stringWithFormat:@"TabState(contentIDs: [%@])", page.identifier];
        DPFakeState *holder = [DPFakeState new];
        holder.currentValue = state;
        row.viewModel = [DPFakeViewModel new];
        row.viewModel.stateSubject = holder;
        [gWindow.contentView addSubview:row];

        gOpened = 0;
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPIgnoreAction, "pinned-only mode takes a new-tab link from a pinned row");
        DPSettle();
        CHECK(gOpened == 1, "a pinned row's link opens in Little Dia");

        PumpFor(0.6);
        gOpened = 0;
        CHECK(DPDecide(page, DPMakeAction(target, DPCurrentTab, 0), DPCurrentTab) == DPIgnoreAction, "a link that leaves a pinned row's site is taken");
        DPSettle();
        CHECK(gOpened == 1, "the off-site link opens in Little Dia");

        gOpened = 0;
        NSString *sameSite = @"https://www.one.example/about";
        CHECK(DPDecide(page, DPMakeAction(sameSite, DPCurrentTab, 0), DPCurrentTab) == DPCurrentTab, "a link on a pinned row's own site stays in the row");
        DPSettle();
        CHECK(gOpened == 0, "same-site links stay put");

        CHECK(gOriginalCalls > 0, "Dia's own handler still runs");

        DPHover(page, @"https://unrelated.example/");
        DPMouseDown();
        DPLittleDiaTabLinks.on = NO;
        DPApplyTabLinks(&DPLittleDiaTabLinks);
        DPHover(page, target);
        DPMouseDown();
        DPHover(page, nil);
        DPLittleDiaTabLinks.on = YES;
        gOpened = 0;
        gChoice = @"all";
        CHECK(DPDecide(page, DPMakeAction(target, DPForegroundTab, 0), DPForegroundTab) == DPForegroundTab, "no mouse-down is recorded while Open Links from Tabs is off");
        DPSettle();
        CHECK(gOpened == 0, "nothing opens without a recorded press");

        if (failures) return 1;
        puts("PASS: Open Links from Tabs hooks Dia's links itself, with no Peek in the process");
    }
    return 0;
}
