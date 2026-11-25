#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"
#import "Patches/DeleteProfileMenu/DeleteProfileMenu.h"
#import "runloop.h"

// Dia isn't here, so every class the tweak touches is faked: a window whose profiles live in Dia's scripting
// layer, a sidebar whose right-click menu is Dia's, a Settings window built inside sendAction:, and a Profiles
// table and confirmation sheet standing in for Dia's. None of them is ever ordered on screen.

static int failures;
static void Expect(BOOL ok, NSString *message) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", message.UTF8String);
}

static int gScriptReads;  // KVC reads of appleScriptProfiles and activeProfile
static int gRowDeletes;   // times Dia's own Delete Profile… ran
static int gCancelPresses;

static NSMutableArray *gKeep;  // windows and controllers kept alive for the whole run
static NSMapTable<NSWindow *, id> *gScripts;
static NSMutableArray<NSWindow *> *gHosts;
static void (^gPendingDelete)(void);  // what Dia's Profiles table does when its Delete Profile… runs

@class DPTestHostWindow;

// Dia's scripting layer: appleScriptProfiles and activeProfile, counted as they're read.
@interface DPTestScriptWindow : NSObject
@property (copy) NSArray *profiles;
@property (strong) id active;
@end

@implementation DPTestScriptWindow
- (id)valueForKey:(NSString *)key {
    if ([key isEqual:@"appleScriptProfiles"] || [key isEqual:@"activeProfile"]) gScriptReads++;
    if ([key isEqual:@"appleScriptProfiles"]) return self.profiles;
    if ([key isEqual:@"activeProfile"]) return self.active;
    return [super valueForKey:key];
}
@end

id DPScriptWindow(NSWindow *window) { return gScripts ? [gScripts objectForKey:window] : nil; }

@interface DPTestProfile : NSObject
@property (copy) NSString *name;
@property NSInteger orderedIndex;
@end

@implementation DPTestProfile
@end

@interface DPTestHostWindow : NSWindow
@property BOOL fakeVisible;
@property int orders;
@property (strong) NSMutableArray<NSWindow *> *sheetWindows;
- (void)attachSheet:(NSWindow *)sheet;
@end

@interface DPTestSheet : NSWindow
@property (weak) DPTestHostWindow *host;
@end

@implementation DPTestSheet
@end

@interface DPTestCancelButton : NSButton
@end

@implementation DPTestCancelButton
- (NSString *)accessibilityLabel { return @"Cancel"; }
- (BOOL)accessibilityPerformPress {
    gCancelPresses++;
    DPTestSheet *sheet = (DPTestSheet *)self.window;
    [sheet.host endSheet:sheet returnCode:NSModalResponseCancel];
    return YES;
}
@end

@implementation DPTestHostWindow
- (BOOL)isVisible { return self.fakeVisible; }
- (NSArray<NSWindow *> *)sheets { return self.sheetWindows ?: @[]; }
- (void)attachSheet:(NSWindow *)sheet {
    if (!self.sheetWindows) self.sheetWindows = [NSMutableArray array];
    [self.sheetWindows addObject:sheet];
}
- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)code {
    if (![self.sheetWindows containsObject:sheet]) return;
    [self.sheetWindows removeObject:sheet];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEndSheetNotification object:self];
}
- (void)makeKeyAndOrderFront:(id)sender {
    self.orders++;
    self.fakeVisible = YES;
}
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other {
    self.orders++;
    self.fakeVisible = place != NSWindowBelow;
}
- (void)orderOut:(id)sender { self.fakeVisible = NO; }
@end

// Dia makes Settings inside sendAction: on the first open in a session, which is the flash this tweak avoids.
@interface _TtC11Preferences25PlatformPreferencesWindow : NSWindow
@property BOOL fakeVisible;
@property int orders, orderOuts, closes;
@property CGFloat alphaWhenOrdered;
@property NSInteger behaviorWhenOrdered;
@property BOOL ignoresWhenOrdered;
@end

@implementation _TtC11Preferences25PlatformPreferencesWindow
- (BOOL)isVisible { return self.fakeVisible; }
- (void)record {
    self.alphaWhenOrdered = self.alphaValue;
    self.behaviorWhenOrdered = self.animationBehavior;
    self.ignoresWhenOrdered = self.ignoresMouseEvents;
    self.orders++;
    self.fakeVisible = YES;
}
- (void)makeKeyAndOrderFront:(id)sender { [self record]; }
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other { [self record]; }
- (void)orderOut:(id)sender {
    self.orderOuts++;
    self.fakeVisible = NO;
}
- (void)close {
    self.closes++;
    self.fakeVisible = NO;
}
@end

@interface _TtC6Dialog27DialogPanelWindowController : NSWindowController
@end

@implementation _TtC6Dialog27DialogPanelWindowController
@end

// Dia's Profiles table: a name per row and the right-click menu that offers Delete Profile….
@interface _TtC11PreferencesP33_6E7E2AAA974892210E333FA6FCBB0CC017ProfilesTableView : NSView
@property (copy) NSArray<NSString *> *rowNames;
@property NSInteger rowClicked;
@end

@implementation _TtC11PreferencesP33_6E7E2AAA974892210E333FA6FCBB0CC017ProfilesTableView
- (NSInteger)numberOfRows { return (NSInteger)self.rowNames.count; }
- (NSRect)rectOfRow:(NSInteger)row { return NSMakeRect(0, row * 22, 200, 20); }
- (NSView *)viewAtColumn:(NSInteger)column row:(NSInteger)row makeIfNecessary:(BOOL)make {
    NSView *cell = [NSView new];
    NSTextField *label = [NSTextField new];
    label.stringValue = row >= 0 && row < (NSInteger)self.rowNames.count ? self.rowNames[row] : @"";
    [cell addSubview:label];
    return cell;
}
- (NSMenu *)menuForEvent:(NSEvent *)event {
    self.rowClicked = (NSInteger)floor([self convertPoint:event.locationInWindow fromView:nil].y / 22);
    NSMenu *menu = [NSMenu new];
    [menu addItem:DPMenuItem(@"Delete Profile…", ^{
        gRowDeletes++;
        if (gPendingDelete) gPendingDelete();
    })];
    return menu;
}
@end

@interface _TtC10TabSidebar15SidebarRootView : NSView
@end

@implementation _TtC10TabSidebar15SidebarRootView
// Dia hands back the menu it keeps, so the tweak has to clean that one up when it's turned off.
- (NSMenu *)menuForEvent:(NSEvent *)event { return self.menu; }
@end

@interface DPTestOpener : NSObject
@property (copy) NSWindow *(^make)(void);
@end

@implementation DPTestOpener
- (void)openSettings:(id)sender { [self.make() makeKeyAndOrderFront:nil]; }
@end

static _TtC11Preferences25PlatformPreferencesWindow *gSettings;
static _TtC11PreferencesP33_6E7E2AAA974892210E333FA6FCBB0CC017ProfilesTableView *gTable;
static NSWindow *gLastSheet;

static NSEvent *DPTestClick(void) {
    return [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0
                          windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
}

static NSMenu *DPTestEditMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context"];
    NSMenuItem *editProfile = [[NSMenuItem alloc] initWithTitle:@"Edit Profile…" action:nil keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit Profile"];
    [edit addItem:[[NSMenuItem alloc] initWithTitle:@"Profile Settings" action:nil keyEquivalent:@""]];
    editProfile.submenu = edit;
    [menu addItem:editProfile];
    return menu;
}

static NSMenu *DPTestEdit(NSMenu *menu) { return [menu itemWithTitle:@"Edit Profile…"].submenu; }

static DPTestHostWindow *DPTestHost(NSArray<NSString *> *names, NSUInteger activeIndex) {
    for (DPTestHostWindow *old in gHosts) old.fakeVisible = NO;
    DPTestHostWindow *host = [[DPTestHostWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                                 styleMask:NSWindowStyleMaskTitled
                                                                   backing:NSBackingStoreBuffered
                                                                     defer:YES];
    host.fakeVisible = YES;
    host.sheetWindows = [NSMutableArray array];
    [gHosts addObject:host];
    NSMutableArray *profiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; i++) {
        DPTestProfile *profile = [DPTestProfile new];
        profile.name = names[i];
        profile.orderedIndex = (NSInteger)i + 1;
        [profiles addObject:profile];
    }
    DPTestScriptWindow *script = [DPTestScriptWindow new];
    script.profiles = profiles.count ? profiles : nil;  // a private window has no profiles at all
    script.active = activeIndex < profiles.count ? profiles[activeIndex] : nil;
    [gScripts setObject:script forKey:host];
    return host;
}

static _TtC10TabSidebar15SidebarRootView *DPTestSidebar(DPTestHostWindow *host) {
    _TtC10TabSidebar15SidebarRootView *sidebar = [[_TtC10TabSidebar15SidebarRootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    sidebar.menu = DPTestEditMenu();
    [host.contentView addSubview:sidebar];
    return sidebar;
}

// Settings as the next delete finds it: the rows to show, opaque, and its counters back to zero. Made inside
// sendAction: the first time, which is what Dia does.
static _TtC11Preferences25PlatformPreferencesWindow *DPTestSettings(NSArray<NSString *> *rows) {
    if (!gSettings) {
        gSettings = [[_TtC11Preferences25PlatformPreferencesWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 420)
                                                                                    styleMask:NSWindowStyleMaskTitled
                                                                                      backing:NSBackingStoreBuffered
                                                                                        defer:YES];
        gTable = [[_TtC11PreferencesP33_6E7E2AAA974892210E333FA6FCBB0CC017ProfilesTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        [gSettings.contentView addSubview:gTable];
        [gKeep addObject:gSettings];
    }
    gTable.rowNames = rows;
    gTable.rowClicked = -1;
    gSettings.fakeVisible = NO;
    gSettings.alphaValue = 1;
    gSettings.animationBehavior = NSWindowAnimationBehaviorDefault;
    gSettings.ignoresMouseEvents = NO;
    gSettings.orders = gSettings.orderOuts = gSettings.closes = 0;
    gSettings.alphaWhenOrdered = 1;
    gSettings.behaviorWhenOrdered = NSWindowAnimationBehaviorDefault;
    gSettings.ignoresWhenOrdered = NO;
    return gSettings;
}

// The menu item whose action Dia's sendAction: runs.
static NSMenuItem *DPTestSettingsItem(NSArray<NSString *> *rows) {
    DPTestOpener *opener = [DPTestOpener new];
    [gKeep addObject:opener];
    opener.make = ^NSWindow *{ return gSettings ?: DPTestSettings(rows); };
    NSMenuItem *item = [NSMenuItem new];
    item.target = opener;
    item.action = @selector(openSettings:);
    return item;
}

// Dia's confirmation: the profile's name in quotes, plus a Cancel button.
static void DPTestAttach(DPTestHostWindow *host, NSString *text, BOOL inField) {
    DPTestSheet *sheet = [[DPTestSheet alloc] initWithContentRect:NSMakeRect(0, 0, 320, 120)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
    sheet.host = host;
    if (inField) {
        NSTextField *label = [NSTextField new];
        label.stringValue = text;
        label.frame = NSMakeRect(10, 10, 300, 20);
        [sheet.contentView addSubview:label];
    } else {
        NSTextView *label = [[NSTextView alloc] initWithFrame:NSMakeRect(10, 10, 300, 60)];
        label.string = text;
        [sheet.contentView addSubview:label];
    }
    [sheet.contentView addSubview:[[DPTestCancelButton alloc] initWithFrame:NSMakeRect(10, 80, 80, 24)]];
    _TtC6Dialog27DialogPanelWindowController *controller = [[_TtC6Dialog27DialogPanelWindowController alloc] initWithWindow:sheet];
    [gKeep addObject:controller];
    gLastSheet = sheet;
    [host attachSheet:sheet];
}

static void DPTestSettle(void) { DPDrainMainQueue(0.2); }

static void DPTestMetadata(void) {
    Expect([DPDeleteProfileMenu.section isEqualToString:@"Profiles"], @"the tweak sits in Profiles, with the other profile tweaks");
    Expect([DPDeleteProfileMenu.tint isEqualToString:@"systemRedColor"], @"its tint is the one the Profiles section uses");
    Expect(DPDeleteProfileMenu.experimental, @"it's experimental");
    Expect([DPDeleteProfileMenu.title isEqualToString:@"Delete Profile from Sidebar"], @"its title is the one Settings, bug.yml and the wiki use");
    Expect(![DPDeleteProfileMenu.detail hasSuffix:@"Experimental."], @"its detail leaves the badge to .experimental");
    Expect([DPDeleteProfileMenu.detail rangeOfString:@"profile’s"].location != NSNotFound, @"its detail keeps the curly apostrophe");
}

static void DPTestOffTweak(void) {
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 1);
    _TtC10TabSidebar15SidebarRootView *sidebar = DPTestSidebar(host);
    DPDeleteProfileMenu.on = YES;
    NSMenu *menu = [sidebar menuForEvent:DPTestClick()];
    NSMenuItem *deleteItem = [DPTestEdit(menu) itemWithTitle:@"Delete Profile…"];
    Expect(deleteItem != nil, @"a window with two profiles gets Delete Profile…");
    Expect([DPTestEdit(menu) indexOfItem:deleteItem] == [DPTestEdit(menu) indexOfItem:[DPTestEdit(menu) itemWithTitle:@"Profile Settings"]] + 1,
           @"and it sits right after Profile Settings");

    gScriptReads = 0;
    DPDeleteProfileMenu.on = NO;
    DPDeleteProfileMenu.apply(&DPDeleteProfileMenu);
    Expect([DPTestEdit(menu) itemWithTitle:@"Delete Profile…"] == nil, @"turning the tweak off takes the item out of the menu Dia kept");
    Expect(gScriptReads == 0, @"and does it without asking Dia about the window's profiles");

    DPDeleteProfileMenu.on = YES;
    menu = [sidebar menuForEvent:DPTestClick()];
    Expect([DPTestEdit(menu) itemWithTitle:@"Delete Profile…"] != nil, @"a new right-click puts a fresh Delete Profile… in");
    DPDeleteProfileMenu.on = NO;
    gScriptReads = 0;
    menu = [sidebar menuForEvent:DPTestClick()];
    Expect([DPTestEdit(menu) itemWithTitle:@"Delete Profile…"] == nil, @"a right-click with the tweak off drops a stale Delete Profile…");
    Expect(gScriptReads == 0, @"and never asks Dia about the window's profiles");
    Expect(DPDeleteProfileMenu.verify(&DPDeleteProfileMenu) == nil, @"and verify finds nothing to complain about either");
}

static void DPTestMenuItems(void) {
    DPDeleteProfileMenu.on = YES;
    DPTestHostWindow *single = DPTestHost(@[ @"Only" ], 0);
    _TtC10TabSidebar15SidebarRootView *sidebar = DPTestSidebar(single);
    Expect([DPTestEdit([sidebar menuForEvent:DPTestClick()]) itemWithTitle:@"Delete Profile…"] == nil,
           @"Dia won't delete a window's last profile, so it isn't offered");

    DPTestHostWindow *private = DPTestHost(@[], 0);
    sidebar = DPTestSidebar(private);
    Expect([DPTestEdit([sidebar menuForEvent:DPTestClick()]) itemWithTitle:@"Delete Profile…"] == nil,
           @"a private window has no profiles, so nothing is offered");

    DPTestHostWindow *two = DPTestHost(@[ @"Work", @"Personal" ], 0);
    sidebar = DPTestSidebar(two);
    Expect([DPTestEdit([sidebar menuForEvent:DPTestClick()]) itemWithTitle:@"Delete Profile…"] != nil, @"two profiles get the item");
    Expect(DPDeleteProfileMenu.verify(&DPDeleteProfileMenu) == nil, @"and verify agrees the menu is right");
}

static void DPTestColdFirstOpen(void) {
    DPDeleteProfileMenu.on = YES;
    Expect(DPSettingsWindow(NO) == nil, @"a fresh session has no Settings window yet");
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 1);
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Personal”? Type the profile’s name.", NO); };
    DPDeleteProfile(host, @"Personal", 1, DPTestSettingsItem(@[ @"Work", @"Personal" ]));
    DPTestSettle();

    Expect(gSettings != nil && gSettings.orders > 0, @"Dia made and ordered Settings inside sendAction:");
    Expect(gSettings.alphaWhenOrdered == 0, @"and it was already see-through when that happened, so nothing flashed");
    Expect(gSettings.behaviorWhenOrdered == NSWindowAnimationBehaviorNone, @"with no open animation to watch");
    Expect(gSettings.ignoresWhenOrdered, @"and no clicks of its own while it's ours");
    Expect(gRowDeletes == 1, @"Dia's own Delete Profile… ran from the Profiles row");
    Expect(gTable.rowClicked == 1, @"on the row of the profile that was picked");
    Expect(DPDeletingProfile(), @"and the delete is in flight");
    Expect(host.sheetWindows.count == 1, @"with Dia's confirmation on the window");
    Expect(gSettings.alphaValue == 0 && gSettings.ignoresMouseEvents, @"Settings stays invisible and untouchable meanwhile");

    [host endSheet:gLastSheet returnCode:NSModalResponseOK];
    DPTestSettle();
    Expect(gSettings.orderOuts == 1, @"confirming orders Settings back out");
    Expect(gSettings.alphaValue == 1, @"and puts its alpha back");
    Expect(gSettings.animationBehavior == NSWindowAnimationBehaviorDefault, @"its animation behaviour back");
    Expect(!gSettings.ignoresMouseEvents, @"and its clicks back");
    Expect(!DPSettingsHidden(gSettings), @"so it isn't left marked hidden");
    Expect(!DPDeletingProfile(), @"the delete is over");
    Expect(gSettings.closes == 0, @"and Dia's reusable window is never closed");
}

static void DPTestAlreadyOpen(void) {
    DPDeleteProfileMenu.on = YES;
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 0);
    DPTestSettings(@[ @"Work", @"Personal" ]);
    int deletes = gRowDeletes;
    gSettings.fakeVisible = YES;  // the user has Settings open already
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Work”?", YES); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();

    Expect(gSettings.alphaWhenOrdered == 1, @"Settings that was already open is never hidden");
    Expect(!gSettings.ignoresWhenOrdered, @"and keeps taking clicks");
    Expect(!DPSettingsHidden(gSettings), @"so the delete leaves it alone");
    Expect(gRowDeletes == deletes + 1 && gTable.rowClicked == 0, @"the delete still runs from its row");

    [host endSheet:gLastSheet returnCode:NSModalResponseOK];
    DPTestSettle();
    Expect(gSettings.fakeVisible, @"and Settings stays on screen when the sheet ends");
    Expect(gSettings.orderOuts == 0, @"nothing orders it out");
    Expect(gSettings.closes == 0, @"and nothing closes it");
    Expect(!DPDeletingProfile(), @"with the delete finished");
}

static void DPTestDuplicateNames(void) {
    DPDeleteProfileMenu.on = YES;
    // Two profiles called Work: the row under the picked index is someone else, so guessing is not allowed.
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Work" ], 1);
    DPTestSettings(@[ @"Personal", @"Other" ]);
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Work”?", NO); };
    int deletes = gRowDeletes;
    DPDeleteProfile(host, @"Work", 1, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(gRowDeletes == deletes, @"two profiles with the same name: no row is guessed and Dia's delete doesn't run");
    Expect(host.sheetWindows.count == 0, @"so no confirmation is put up either");
    Expect(!DPDeletingProfile(), @"and the next delete isn't wedged");
    Expect(gSettings.fakeVisible, @"Settings comes up on Profiles instead, so the delete can be finished by hand");

    // One Work, in another row: the row is then found by its name alone.
    host = DPTestHost(@[ @"Work", @"Personal" ], 0);
    DPTestSettings(@[ @"Personal", @"Work" ]);
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Work”?", YES); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(gRowDeletes == deletes + 1 && gTable.rowClicked == 1, @"a unique name is found in whichever row holds it");
    [host endSheet:gLastSheet returnCode:NSModalResponseOK];
    DPTestSettle();
    Expect(!DPDeletingProfile(), @"and the delete finishes");
}

static void DPTestWrongSheet(void) {
    DPDeleteProfileMenu.on = YES;
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 0);
    DPTestSettings(@[ @"Work", @"Personal" ]);

    // Straight quotes, in a text field: still the profile the user picked.
    gPendingDelete = ^{ DPTestAttach(host, @"Delete \"Work\"? Type the profile’s name.", YES); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(DPDeletingProfile() && host.sheetWindows.count == 1, @"a sheet naming the profile in straight quotes is accepted");
    Expect(gCancelPresses == 0, @"so it isn't cancelled");
    [host endSheet:gLastSheet returnCode:NSModalResponseOK];
    DPTestSettle();
    Expect(!DPDeletingProfile(), @"and the delete finishes");

    // A sheet naming someone else has to be cancelled, not hidden behind.
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Personal”?", NO); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(gCancelPresses == 1, @"a sheet naming another profile has its Cancel pressed");
    Expect(host.sheetWindows.count == 0, @"and is taken down");
    Expect(!DPDeletingProfile(), @"so the next delete isn't wedged");
    Expect(!DPSettingsHidden(gSettings), @"and Settings is put back as it was");
    Expect(!gSettings.fakeVisible, @"left out of sight, as it was before");
}

static void DPTestTurnOff(void) {
    DPDeleteProfileMenu.on = YES;
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 0);
    DPTestSettings(@[ @"Work", @"Personal" ]);
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Work”?", NO); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(DPDeletingProfile(), @"the delete is in flight");
    gCancelPresses = 0;

    DPDeleteProfileMenu.on = NO;
    DPDeleteProfileMenu.apply(&DPDeleteProfileMenu);
    Expect(gCancelPresses == 1, @"turning the tweak off cancels the confirmation");
    Expect(host.sheetWindows.count == 0, @"and takes it down");
    Expect(!DPDeletingProfile(), @"so nothing is left wedged");
    Expect(!DPSettingsHidden(gSettings), @"Settings is put back");
    Expect(gSettings.alphaValue == 1 && gSettings.animationBehavior == NSWindowAnimationBehaviorDefault && !gSettings.ignoresMouseEvents,
           @"with its alpha, animation behaviour and clicks");
    Expect(!gSettings.fakeVisible, @"and stays out of sight");
}

static void DPTestSettingsTakesOver(void) {
    DPDeleteProfileMenu.on = YES;
    DPTestHostWindow *host = DPTestHost(@[ @"Work", @"Personal" ], 0);
    DPTestSettings(@[ @"Work", @"Personal" ]);
    gPendingDelete = ^{ DPTestAttach(host, @"Delete “Work”?", NO); };
    DPDeleteProfile(host, @"Work", 0, DPTestSettingsItem(@[]));
    DPTestSettle();
    Expect(DPDeletingProfile() && DPSettingsHidden(gSettings), @"the delete runs with Settings hidden");

    // ⌘, brings Settings to the front: from then on it's the user's.
    gSettings.fakeVisible = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:gSettings];
    Expect(!DPSettingsHidden(gSettings), @"pressing ⌘, hands Settings back");
    Expect(gSettings.alphaValue == 1 && !gSettings.ignoresMouseEvents, @"with its alpha and clicks");

    [host endSheet:gLastSheet returnCode:NSModalResponseOK];
    DPTestSettle();
    Expect(!DPDeletingProfile(), @"and the delete can still finish");
    Expect(gSettings.fakeVisible && gSettings.orderOuts == 0, @"leaving the Settings the user opened alone");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-delete-profile-%d", getpid()]];
        [NSFileManager.defaultManager createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:NULL];
        setenv("DIAPATCH_HOME", scratch.fileSystemRepresentation, 1);
        NSString *domain = [NSString stringWithFormat:@"com.diapatches.test.delete-profile.%d", getpid()];
        setenv("DIATWEAKS_DOMAIN", domain.fileSystemRepresentation, 1);

        gKeep = [NSMutableArray array];
        gHosts = [NSMutableArray array];
        gScripts = [NSMapTable weakToStrongObjectsMapTable];
        // Dia's tab strip has a dotted Swift name, which only the runtime can make, and it just has to exist to be hooked.
        objc_registerClassPair(objc_allocateClassPair(NSView.class, "TabStrip.TabStripContainerView", 0));
        objc_registerClassPair(objc_allocateClassPair(NSView.class, "_TtC10TabSidebarP33_1737451677CA9CA733FCF78BBDD9DE8A24SidebarContainerRootView", 0));

        DPDeleteProfileMenu.on = NO;
        DPDeleteProfileMenu.install();

        DPTestMetadata();
        DPTestOffTweak();
        DPTestMenuItems();
        DPTestColdFirstOpen();
        DPTestAlreadyOpen();
        DPTestDuplicateNames();
        DPTestWrongSheet();
        DPTestTurnOff();
        DPTestSettingsTakesOver();

        [NSFileManager.defaultManager removeItemAtPath:scratch error:NULL];
        [DPSettingsDefaults() removePersistentDomainForName:domain];
        if (failures) printf("%d delete-profile-menu checks failed\n", failures);
        else printf("delete-profile-menu: all checks passed\n");
        return failures ? 1 : 0;
    }
}
