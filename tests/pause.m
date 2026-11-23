#import <dlfcn.h>
#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"

static NSString *DPPauseTestDomain(void) { return [NSString stringWithFormat:@"com.diapatches.pause-test.%d", getpid()]; }

@interface NSUserDefaults (DPPauseTest)
- (instancetype)dp_pauseInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPPauseTest)
- (instancetype)dp_pauseInitWithSuiteName:(NSString *)suite {
    return [self dp_pauseInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPPauseTestDomain() : suite];
}
@end
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"

void DPApplyHides(DPPatch *patch) {}
NSString *DPVerifyHides(DPPatch *patch) { return nil; }
void DPInstallHides(void) {}
void DPOnLaunch(void (^block)(void)) {}
void DPOnQuit(void (^block)(void)) {}
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
NSString *const DPDia = @"dia", *const DPTweaks = @"tweaks";
NSNotificationName const DPUpdatesDidChangeNotification = @"DPUpdatesDidChange";

static NSArray<NSString *> *lastHandOff, *lastCLI;
void DPHandOffAndQuit(NSArray<NSString *> *args) { lastHandOff = args; }
void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) {
    lastCLI = args;
    if (completion) completion(@"");
}

@implementation DPPreviewView
- (instancetype)initWithKey:(NSString *)key { return [super initWithFrame:NSZeroRect]; }
@end

@implementation DPSoftwareUpdateView
@end

@implementation DPUpdates
+ (instancetype)shared {
    static DPUpdates *shared;
    if (!shared) shared = [DPUpdates new];
    return shared;
}
- (void)check:(void (^)(void))done {}
- (BOOL)available:(NSString *)part { return NO; }
- (BOOL)staged:(NSString *)part { return NO; }
- (BOOL)downloading:(NSString *)part { return NO; }
- (BOOL)failed:(NSString *)part { return NO; }
- (NSString *)failure:(NSString *)part { return nil; }
- (double)progress:(NSString *)part { return 0; }
- (void)download:(NSString *)part then:(void (^)(void))done {}
- (void)installAndRelaunch:(NSArray<NSString *> *)parts {}
- (void)pretend:(NSString *)part {}
- (void)stopPretending {}
@end

static const char *DPTestDylib;
static int DPTestDladdr(const void *address, Dl_info *info) {
    int found = dladdr(address, info);
    info->dli_fname = DPTestDylib;
    return found;
}
#define dladdr DPTestDladdr

static int applied;
static BOOL lastOn;
static void DPApplyStub(DPPatch *patch) {
    applied++;
    lastOn = patch->on;
}

static NSMenu *DPStubChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Style"];
    [menu addItemWithTitle:@"One" action:nil keyEquivalent:@""].representedObject = @"one";
    [menu addItemWithTitle:@"Two" action:nil keyEquivalent:@""].representedObject = @"two";
    return menu;
}

static NSDictionary *DPStubShortcut(void) {
    return @{ @"keyCode" : @5, @"modifiers" : @(NSEventModifierFlagCommand), @"key" : @"G" };
}

@interface DPCustomEnabledRow : NSView
@property (nonatomic) BOOL enabled;
@property (nonatomic, strong) NSButton *childButton;
@property (nonatomic) NSInteger setEnabledCount;
@end
@implementation DPCustomEnabledRow
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _childButton = [NSButton buttonWithTitle:@"Relaunch" target:nil action:nil];
    _childButton.enabled = NO;
    [self addSubview:_childButton];
    return self;
}
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    _setEnabledCount++;
    // Intentionally keep _childButton disabled (e.g. invalid input or no pending changes).
    _childButton.enabled = NO;
}
@end

static DPCustomEnabledRow *gCustomRow;
static NSArray<NSView *> *DPStubCustomRows(void) {
    gCustomRow = [[DPCustomEnabledRow alloc] initWithFrame:NSMakeRect(0, 0, 300, 40)];
    return @[ gCustomRow ];
}

DP_PATCH(DPStub) {
    .key = @"pauseTest",
    .title = @"Pause Test",
    .detail = @"",
    .symbol = @"star.fill",
    .tint = @"systemBlueColor",
    .section = @"Test",
    .choice = @"pauseTestChoice",
    .defaultChoice = @"one",
    .choices = DPStubChoices,
    .shortcut = @"pauseTestShortcut",
    .defaultShortcut = DPStubShortcut,
    .rows = DPStubCustomRows,
    .apply = DPApplyStub,
};

DP_PATCH(DPSubOptionStub) {
    .key = @"pauseSubOption",
    .title = @"Sub Option",
    .detail = @"",
    .symbol = @"star.fill",
    .tint = @"systemBlueColor",
    .requires = @"pauseTest",
    .choice = @"pauseSubChoice",
    .defaultChoice = @"one",
    .choices = DPStubChoices,
    .apply = DPApplyStub,
};

DP_PATCH(DPRelaunchStub) {
    .key = @"pauseRelaunchTest",
    .title = @"Relaunch Test",
    .detail = @"",
    .symbol = @"star.fill",
    .tint = @"systemBlueColor",
    .section = @"Test",
    .relaunch = YES,
};

#import "SafeMode/SafeMode.m"
#import "StdPatch/Patch.m"
#import "Local/Local.m"
#import "Local/Build.m"
#import "Local/Extract.m"
#import "Local/State.m"
#import "StdPatch/Shortcut.m"
#import "Settings/Controls.m"
#import "Settings/Items.m"
#import "Settings/Overview.m"
#import "Settings/Folder.m"
#import "Settings/Home.m"
#import "Settings/Page.m"

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static NSButton *findButton(NSView *root, BOOL (^match)(NSButton *)) {
    return (NSButton *)DPFindView(root, ^BOOL(NSView *v) { return [v isKindOfClass:NSButton.class] && match((NSButton *)v); });
}

static NSTextField *findLabel(NSView *root, NSString *text) {
    return (NSTextField *)DPFindView(root, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextField.class] && [((NSTextField *)v).stringValue isEqual:text]; });
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_pauseInitWithSuiteName:)));
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        NSString *support = [temporary stringByAppendingPathComponent:@"support"];
        [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
        DPTestDylib = [[support stringByAppendingPathComponent:@"DiaPatches.dylib"] fileSystemRepresentation];
        NSString *pause = [support stringByAppendingPathComponent:@"paused"];

        // Registered defaults avoid writing to disk.
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
        [defaults registerDefaults:@{ @"pauseTest" : @YES, @"pauseSubOption" : @YES, @"pauseRelaunchTest" : @NO }];
        DPDefaults = defaults;
        static DPPatch *patches[] = { &DPStub, &DPSubOptionStub, &DPRelaunchStub };
        DPPatches = patches;
        DPPatchCount = 3;

        DPBeginLaunch();
        expect(!DPPaused && !DPPausedAtLaunch, @"a launch without the pause file isn't paused");
        for (NSUInteger i = 0; i < DPPatchCount; i++) {
            DPPatches[i]->on = DPEffectiveOn(DPPatches[i]);
            DPRecordChoice(DPPatches[i]);
        }
        expect(DPSavedOn(&DPStub) && DPStub.on, @"it starts on, as saved");

        [NSData.data writeToFile:pause atomically:YES];
        DPApplySavedSettings();
        expect(DPPaused && !DPStub.on && applied == 2 && !lastOn, @"pausing turns it off");
        expect(DPSavedOn(&DPStub), @"pausing keeps its saved setting");

        DPSetPatch(&DPStub, YES, NO);
        expect(!DPStub.on && applied == 2, @"a tweak can't be turned on while paused");

        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPApplySavedSettings();
        expect(!DPPaused && DPStub.on && applied == 4 && lastOn, @"resuming turns it back on");

        DPOverviewView *overview = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 600)];
        DPHomeView *home = [[DPHomeView alloc] initWithFrame:NSMakeRect(0, 0, 560, 600)];
        DPPageView *page = [[DPPageView alloc] initWithPatch:&DPStub];
        NSTextField *pausedHeader = findLabel(overview, @"Paused");
        NSButton *overviewPause = findButton(overview, ^BOOL(NSButton *b) { return [b.title isEqual:@"Pause Tweaks"]; });
        NSButton *homePause = findButton(home, ^BOOL(NSButton *b) { return [b.title isEqual:@"Pause Tweaks"]; });
        DPPatchSwitch *stubSwitch = (DPPatchSwitch *)DPFindView(overview, ^BOOL(NSView *v) { return [v isKindOfClass:DPPatchSwitch.class] && ((DPPatchSwitch *)v).patch == &DPStub; });
        NSPopUpButton *picker = (NSPopUpButton *)DPFindView(page, ^BOOL(NSView *v) { return [v isKindOfClass:NSPopUpButton.class]; });
        DPShortcutButton *shortcut = (DPShortcutButton *)DPFindView(page, ^BOOL(NSView *v) { return [v isKindOfClass:DPShortcutButton.class]; });

        expect(overviewPause && !overviewPause.hiddenOrHasHiddenAncestor, @"Patches shows a Pause Tweaks button while unpaused");
        expect(pausedHeader && pausedHeader.hidden, @"Patches hides the Paused header while unpaused");
        expect(homePause != nil, @"Home shows a Pause Tweaks button");
        expect(stubSwitch.state == NSControlStateValueOn && stubSwitch.enabled, @"switch starts on and enabled");
        expect(picker.enabled && shortcut.enabled, @"page choice picker and shortcut button start enabled");
        expect(gCustomRow && gCustomRow.enabled && !gCustomRow.childButton.enabled,
               @"DPSetRowControlsEnabled stops at custom row setEnabled: without clobbering disabled child controls");

        DPSetChoice(&DPStub, @"two");
        [page sync];
        expect([picker.selectedItem.representedObject isEqual:@"two"], @"DPSetChoice updates picker selection on sync");
        int appliedChoiceBefore = applied;
        [defaults setObject:@"one" forKey:DPStub.choice];
        DPApplySavedSettings();
        [page sync];
        expect(applied == appliedChoiceBefore + 1 && [picker.selectedItem.representedObject isEqual:@"one"],
               @"DPApplySavedSettings re-applies externally changed choice while patch stays on");

        NSPopUpButton *subPicker = (NSPopUpButton *)DPFindView(page, ^BOOL(NSView *v) { return [v isKindOfClass:NSPopUpButton.class] && v != picker; });
        expect(subPicker && subPicker.enabled, @"sub-option picker starts enabled when parent is on");
        DPSetPatch(&DPStub, NO, NO);
        [page sync];
        expect(!subPicker.enabled && !shortcut.enabled && !shortcut.acceptsFirstResponder, @"parent off disables sub-option picker and shortcut button");
        DPSetPatch(&DPStub, YES, NO);
        [page sync];
        expect(subPicker.enabled && shortcut.enabled, @"parent back on re-enables sub-option picker and shortcut button");

        [overview syncWithQuery:@"relaunch"];
        expect(overviewPause.hiddenOrHasHiddenAncestor, @"unrelated search hides the pause row");
        [overview syncWithQuery:@"pause"];
        expect(!overviewPause.hiddenOrHasHiddenAncestor && pausedHeader.hidden, @"searching pause finds the row without the Paused header");
        [overview syncWithQuery:@""];

        int appliedBeforePause = applied;
        lastHandOff = nil;
        [overviewPause performClick:nil];
        [overview syncWithQuery:@""];
        [page sync];
        expect(DPPaused && DPPauseSaved() && !DPStub.on && applied == appliedBeforePause + 2 && !lastOn, @"Settings Pause turns tweaks off and writes paused");
        expect(!lastHandOff, @"Settings Pause does not relaunch when no launch-time tweak is on");
        expect(DPSavedOn(&DPStub) && stubSwitch.state == NSControlStateValueOn && !stubSwitch.enabled, @"switch keeps its saved state and disables");
        expect(!picker.enabled && !subPicker.enabled && !shortcut.enabled, @"pickers and shortcut button disable while paused");
        expect(!subPicker.hiddenOrHasHiddenAncestor, @"sub-option choice stays visible (disabled) while paused");
        expect(!pausedHeader.hidden && [overviewPause.title isEqual:@"Resume Tweaks"], @"Patches shows Paused header and Resume Tweaks");
        expect([homePause.title isEqual:@"Resume Tweaks"], @"Home syncs to Resume Tweaks via notification");

        [homePause performClick:nil];
        [overview syncWithQuery:@""];
        [page sync];
        expect(!DPPaused && !DPPauseSaved() && DPStub.on && applied == appliedBeforePause + 4 && lastOn, @"Settings Resume turns tweaks back on live");
        expect(!lastHandOff, @"Settings Resume does not relaunch when Dia started unpaused");
        expect(pausedHeader.hidden && [overviewPause.title isEqual:@"Pause Tweaks"] && [homePause.title isEqual:@"Pause Tweaks"], @"both panes return to Pause Tweaks");
        expect(stubSwitch.enabled && picker.enabled && subPicker.enabled && shortcut.enabled, @"switch, pickers and shortcut re-enable on resume");

        expect(DPRelaunchingOnPause().count == 0, @"no launch-time tweaks listed when none are on");
        DPRelaunchStub.on = YES;
        expect([DPRelaunchingOnPause() isEqual:@[@"Relaunch Test"]], @"active launch-time tweak is named for relaunch");
        DPRelaunchStub.on = NO;

        [NSData.data writeToFile:pause atomically:YES];
        DPBeginLaunch();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->on = DPEffectiveOn(DPPatches[i]);
        expect(DPPaused && DPPausedAtLaunch && !DPStub.on && DPSavedOn(&DPStub), @"a launch while paused starts with it off");
        [overview syncWithQuery:@""];
        [home refresh];
        expect([overviewPause.title isEqual:@"Resume and Relaunch"] && [homePause.title isEqual:@"Resume and Relaunch"], @"paused launch labels the button Resume and Relaunch");

        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPApplySavedSettings();
        [overview syncWithQuery:@""];
        [home refresh];
        expect(!DPPaused && DPPausedAtLaunch && [overviewPause.title isEqual:@"Relaunch"] && [homePause.title isEqual:@"Relaunch"],
               @"external resume after paused launch prompts Relaunch");
        lastHandOff = nil;
        [overviewPause performClick:nil];
        expect([lastHandOff isEqual:@[@"apply"]], @"clicking Relaunch after external resume hands off to diapatch apply");

        [NSData.data writeToFile:pause atomically:YES];
        DPBeginLaunch();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->on = DPEffectiveOn(DPPatches[i]);
        [overview syncWithQuery:@""];
        int appliedBefore = applied;
        lastHandOff = nil;
        [overviewPause performClick:nil];
        expect(!DPPaused && !DPPauseSaved(), @"Resume and Relaunch clears the pause file");
        expect([lastHandOff isEqual:@[@"apply"]], @"Resume and Relaunch hands off to diapatch apply");
        expect(applied == appliedBefore, @"paused launch does not run live apply handlers");

        DPSafeMode = 1;
        DPPaused = NO;
        [overview syncWithQuery:@""];
        expect(overviewPause.hiddenOrHasHiddenAncestor, @"Safe Mode hides the unpaused pause row on Patches");
        DPSetPaused(YES);
        [overview syncWithQuery:@""];
        expect(!overviewPause.hiddenOrHasHiddenAncestor && [overviewPause.title isEqual:@"Resume Tweaks"], @"Safe Mode + Paused shows Resume Tweaks");
        lastHandOff = nil;
        [overviewPause performClick:nil];
        expect(!DPPaused && !DPPauseSaved() && !lastHandOff, @"resuming in Safe Mode clears pause without relaunching");
        DPSafeMode = 0;

        DPSetPaused(YES);
        DPLeaveSafeMode();
        expect(DPPauseSaved(), @"leaving safe mode leaves the pause alone");

        static DPPatch DPClashStub = {
            .key = @"clashTest", .title = @"Clash Test", .detail = @"", .symbol = @"star.fill", .tint = @"systemBlueColor",
            .section = @"Test", .shortcut = @"clashTestShortcut", .defaultShortcut = DPStubShortcut,
        };
        static DPPatch *withClash[] = { &DPStub, &DPSubOptionStub, &DPRelaunchStub, &DPClashStub };
        DPPatches = withClash;
        DPPatchCount = 4;
        NSStackView *clashColumn = (NSStackView *)DPShortcutRow(&DPStub);
        expect(clashColumn.edgeInsets.bottom == 8, @"DPShortcutRow applies initial clash bottom edgeInset");
        DPShortcutButton *clashButton = (DPShortcutButton *)DPFindView(clashColumn, ^BOOL(NSView *v) { return [v isKindOfClass:DPShortcutButton.class]; });
        NSWindow *shortcutWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        shortcutWindow.contentView = clashColumn;
        [shortcutWindow makeFirstResponder:clashButton];
        [clashButton startRecording];
        expect(clashButton.monitor != nil, @"shortcut button starts recording");
        NSEvent *backspace = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:shortcutWindow.windowNumber context:nil characters:@"\x7f" charactersIgnoringModifiers:@"\x7f" isARepeat:NO keyCode:kVK_Delete];
        [clashButton record:backspace];
        expect(clashButton.monitor == nil && [clashButton.label.stringValue isEqual:@"Add new…"], @"Backspace clears shortcut and stops recording");

        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:DPPauseTestDomain()];
        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
    }
    if (!failures) printf("all pause checks passed\n");
    return failures ? 1 : 0;
}
