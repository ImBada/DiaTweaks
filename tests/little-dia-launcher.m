#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "Patches/LittleDia/LittleDia.h"

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
BOOL DPLittleDiaReady(void) { return YES; }
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

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
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

        if (failures) return 1;
        puts("PASS: Little Dia launcher opens, resolves URLs and searches, and dismisses cleanly");
    }
    return 0;
}
