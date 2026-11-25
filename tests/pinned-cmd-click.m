#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPPinnedCmdClick;

static int gOriginalCalls;
static NSEventModifierFlags gModifiers;
static NSUInteger gPressedButtons;
static NSEvent *gCurrentEvent;

static NSEventModifierFlags DPEvent_modifierFlags(NSEvent *self, SEL _cmd) { return gModifiers; }
static NSUInteger DPEvent_pressedMouseButtons(NSEvent *self, SEL _cmd) { return gPressedButtons; }
static NSWindow *gKeyWindow;
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gKeyWindow; }
static NSEvent *DPApp_currentEvent(NSApplication *self, SEL _cmd) { return gCurrentEvent; }

static NSWindow *gWindow, *gOtherWindow;
static NSMapTable *gOwners;
id DPBrowserOfContents(id contents) { return contents; }
NSWindow *DPBrowserWindow(id browser) { return [gOwners objectForKey:browser] ?: gWindow; }
NSString *DPText(id value) { return [value isKindOfClass:NSString.class] ? value : [value description]; }
id DPMsg(id object, SEL sel) { return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil; }
BOOL DPMsgBool(id object, SEL sel) { return [object respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(object, sel); }
void DPOnLaunch(void (^block)(void)) { block(); }

@interface DPFakeTabState : NSObject
@property (nonatomic, copy) NSString *text, *selectionStyle;
@end
@implementation DPFakeTabState
- (NSString *)description { return self.text; }
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"selectionStyle"] ? self.selectionStyle : nil; }
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

@interface DPFakePage : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSURL *url;
@end
@implementation DPFakePage
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"identifier"] ? self.identifier : nil; }
@end

@interface DPUnpinTarget : NSObject
@property (nonatomic) int unpins;
@end
@implementation DPUnpinTarget
- (void)unpin:(id)sender { self.unpins++; }
@end

@interface _TtC5TabUI7TabView : NSView
@property (nonatomic, strong) DPFakeViewModel *viewModel;
@property (nonatomic, strong) NSMenu *contextMenu;
@end
@implementation _TtC5TabUI7TabView
- (id)safeSwiftValueForKey:(NSString *)key { return [key isEqual:@"viewModel"] ? self.viewModel : nil; }
- (NSMenu *)menuForEvent:(NSEvent *)event { return self.contextMenu; }
@end

@interface _TtC3ADK18WebContentChromium : NSObject
- (void)webContents:(id)webContents didCreateNewWebContent:(id)newContent targetURL:(NSURL *)url disposition:(NSInteger)disposition;
@end
@implementation _TtC3ADK18WebContentChromium
- (void)webContents:(id)webContents didCreateNewWebContent:(id)newContent targetURL:(NSURL *)url disposition:(NSInteger)disposition { gOriginalCalls++; }
@end

@interface DPVisibleWindow : NSWindow
@end
@implementation DPVisibleWindow
- (BOOL)isVisible { return YES; }
@end

#import "Patches/PinnedCmdClick/PinnedCmdClick.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void PumpUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void PumpFor(NSTimeInterval seconds) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static _TtC5TabUI7TabView *gSourceTab, *gNewTab, *gRegularTab;
static DPUnpinTarget *gSourceTarget, *gNewTarget;

static DPFakePage *DPMakePage(NSString *identifier, NSString *url) {
    DPFakePage *page = [DPFakePage new];
    page.identifier = identifier;
    page.url = [NSURL URLWithString:url];
    return page;
}

// A tab row whose context menu offers `item`, as a pinned row's offers Unpin.
static void DPShowTabFor(_TtC5TabUI7TabView *tab, DPFakePage *page, NSString *item, DPUnpinTarget *target, BOOL selected) {
    DPFakeTabState *tabState = [DPFakeTabState new];
    tabState.text = [NSString stringWithFormat:@"TabState(contentIDs: [%@])", page.identifier];
    tabState.selectionStyle = selected ? @"selected" : @"none";
    DPFakeState *state = [DPFakeState new];
    state.currentValue = tabState;
    DPFakeViewModel *model = [DPFakeViewModel new];
    model.stateSubject = state;
    tab.viewModel = model;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    [menu addItemWithTitle:item action:@selector(unpin:) keyEquivalent:@""].target = target;
    tab.contextMenu = menu;
}

static void DPClick(DPFakePage *source, DPFakePage *opened, NSInteger disposition) {
    _TtC3ADK18WebContentChromium *contents = [_TtC3ADK18WebContentChromium new];
    [contents webContents:source didCreateNewWebContent:opened targetURL:opened.url disposition:disposition];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(object_getClass(NSEvent.class), @selector(modifierFlags), (IMP)DPEvent_modifierFlags);
        DPHookClass(object_getClass(NSEvent.class), @selector(pressedMouseButtons), (IMP)DPEvent_pressedMouseButtons);
        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);
        DPHookClass(NSApp.class, @selector(currentEvent), (IMP)DPApp_currentEvent);

        gWindow = [[DPVisibleWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered defer:NO];
        gSourceTab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 30)];
        gNewTab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 40, 200, 30)];
        gRegularTab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 80, 200, 30)];
        [gWindow.contentView addSubview:gSourceTab];
        [gWindow.contentView addSubview:gNewTab];
        [gWindow.contentView addSubview:gRegularTab];
        gKeyWindow = gWindow;
        gSourceTarget = [DPUnpinTarget new];
        gNewTarget = [DPUnpinTarget new];

        DPPinnedCmdClick.on = YES;
        DPPinnedCmdClick.install();

        DPFakePage *pinned = DPMakePage(@"11111111-1111-1111-1111-111111111111", @"https://pinned.example/");
        DPFakePage *opened = DPMakePage(@"22222222-2222-2222-2222-222222222222", @"https://opened.example/");
        DPFakePage *regular = DPMakePage(@"44444444-4444-4444-4444-444444444444", @"https://regular.example/");
        DPShowTabFor(gSourceTab, pinned, @"Unpin", gSourceTarget, YES);
        DPShowTabFor(gNewTab, opened, @"Unpin", gNewTarget, NO);
        DPShowTabFor(gRegularTab, regular, @"Close Tab", nil, NO);

        gModifiers = NSEventModifierFlagCommand;
        DPClick(pinned, opened, DPBackgroundTab);
        PumpUntil(^{ return (BOOL)(gNewTarget.unpins > 0); });
        CHECK(gNewTarget.unpins == 1, "a ⌘-click in a pinned tab unpins the new tab");
        CHECK(gSourceTarget.unpins == 0, "the source pinned tab is left pinned");
        CHECK(gOriginalCalls == 1, "the original handler still runs");

        gNewTarget.unpins = 0;
        gModifiers = 0;
        DPClick(pinned, opened, DPBackgroundTab);
        PumpUntil(^{ return (BOOL)(gNewTarget.unpins > 0); });
        CHECK(gNewTarget.unpins == 1, "a middle-click in a pinned tab unpins the new tab");

        gNewTarget.unpins = 0;
        gModifiers = 0;
        DPClick(pinned, opened, DPForegroundTab);
        PumpFor(0.1);
        CHECK(gNewTarget.unpins == 0, "a plain click is left alone");

        gNewTarget.unpins = 0;
        gModifiers = NSEventModifierFlagCommand;
        DPClick(pinned, opened, DPForegroundTab);
        PumpUntil(^{ return (BOOL)(gNewTarget.unpins > 0); });
        CHECK(gNewTarget.unpins == 1, "a ⌘-click that opens a foreground tab is unpinned");

        gNewTarget.unpins = 0;
        gModifiers = 0;
        gPressedButtons = 4;
        DPClick(pinned, opened, DPForegroundTab);
        PumpUntil(^{ return (BOOL)(gNewTarget.unpins > 0); });
        CHECK(gNewTarget.unpins == 1, "a middle-click that opens a foreground tab is unpinned");
        gPressedButtons = 0;

        // The click's ⌘ can be read from the current event when NSEvent.modifierFlags is already clear.
        gNewTarget.unpins = 0;
        gModifiers = 0;
        gCurrentEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                        timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@""
                                         isARepeat:NO keyCode:0];
        DPClick(pinned, opened, DPForegroundTab);
        PumpUntil(^{ return (BOOL)(gNewTarget.unpins > 0); });
        CHECK(gNewTarget.unpins == 1, "the current event's ⌘ modifier counts");
        gCurrentEvent = nil;

        gNewTarget.unpins = 0;
        gModifiers = NSEventModifierFlagCommand;
        DPClick(regular, opened, DPBackgroundTab);
        PumpFor(0.1);
        CHECK(gNewTarget.unpins == 0, "an unpinned source tab is left alone");

        gNewTarget.unpins = 0;
        DPShowTabFor(gNewTab, opened, @"Unpin", nil, NO);
        gModifiers = NSEventModifierFlagCommand;
        DPClick(pinned, opened, DPBackgroundTab);
        PumpFor(1.2);
        CHECK(gNewTarget.unpins == 0, "a nil-target Unpin item is refused");
        DPPinnedCmdClick.on = NO;
        PumpFor(0.3);
        DPPinnedCmdClick.on = YES;
        DPShowTabFor(gNewTab, opened, @"Unpin", gNewTarget, NO);

        gNewTarget.unpins = 0;
        gOtherWindow = [[DPVisibleWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300) styleMask:NSWindowStyleMaskBorderless
                                                           backing:NSBackingStoreBuffered defer:NO];
        DPFakePage *stray = DPMakePage(@"33333333-3333-3333-3333-333333333333", @"https://stray.example/");
        gOwners = [NSMapTable weakToWeakObjectsMapTable];
        [gOwners setObject:gOtherWindow forKey:stray];
        DPClick(stray, opened, DPBackgroundTab);
        PumpFor(0.2);
        CHECK(gNewTarget.unpins == 0, "a link from another window's unpinned tab ignores the key window's pinned selection");

        gNewTarget.unpins = 0;
        DPPinnedCmdClick.on = NO;
        DPClick(pinned, opened, DPBackgroundTab);
        PumpFor(0.1);
        CHECK(gNewTarget.unpins == 0, "the hook is a no-op when the tweak is off");
        CHECK(gOriginalCalls == 10, "the original handler still runs when off");

        if (failures) return 1;
        puts("PASS: Pinned Tabs unpins tabs opened by ⌘-click or middle-click from a pinned tab");
    }
    return 0;
}
