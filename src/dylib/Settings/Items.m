#import "Settings.h"

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option)) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *option = DPPatches[i];
        if (DPRequired(option) != patch) continue;
        body(option);
        DPForEachOption(option, body);
    }
}

NSArray<NSValue *> *DPFolderMembers(NSString *key) {
    NSMutableArray<NSValue *> *members = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->group && [DPPatches[i]->group isEqualToString:key]) [members addObject:[NSValue valueWithPointer:DPPatches[i]]];
    return members;
}

BOOL DPShownOn(DPPatch *patch) { return patch && (DPPaused ? DPSavedOn(patch) : patch->on); }

static NSString *const DPShowsExperimentalKey = @"showExperimentalTweaks";

BOOL DPShowsExperimental(void) { return [DPSettingsDefaults() boolForKey:DPShowsExperimentalKey]; }

void DPSetShowsExperimental(BOOL on) {
    [DPSettingsDefaults() setBool:on forKey:DPShowsExperimentalKey];
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

BOOL DPExperimentalShown(DPPatch *patch) {
    if (!patch->experimental || DPShowsExperimental() || DPShownOn(patch)) return YES;
    __block BOOL shown = NO;
    DPForEachOption(patch, ^(DPPatch *option) { shown |= option->experimental && DPShownOn(option); });
    return shown;
}

NSArray<NSValue *> *DPShownMembers(NSArray<NSValue *> *members) {
    NSMutableArray<NSValue *> *shown = [NSMutableArray new];
    for (NSValue *member in members)
        if (DPExperimentalShown(member.pointerValue)) [shown addObject:member];
    return shown;
}

NSUInteger DPHiddenExperimentalCount(void) {
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < DPPatchCount; i++) count += !DPExperimentalShown(DPPatches[i]);
    return count;
}

NSString *DPActiveSummary(DPPatch *patch) {
    NSString *why = DPWhyDisabled(patch);
    if (why || !DPShownOn(patch)) return why;
    NSMutableArray<NSString *> *options = [NSMutableArray new];
    DPForEachOption(patch, ^(DPPatch *option) {
        if (DPShownOn(option)) [options addObject:option->title];
    });
    return [options componentsJoinedByString:@" · "];
}

NSString *DPWhyDisabled(DPPatch *patch) {
    if (patch->unavailable) return @"Unavailable on this Dia version.";
    NSString *problem = DPLocalProblem(patch);
    if (problem) return problem;
    int hops = 0;
    for (DPPatch *required = DPRequired(patch); required && hops++ < 32; required = DPRequired(required))
        if (!DPShownOn(required)) return [NSString stringWithFormat:@"Needs %@.", required->title];
    DPPatch *cover = DPPatchNamed(patch->coveredBy);
    return DPShownOn(cover) ? [NSString stringWithFormat:@"%@ hides this too.", cover->title] : nil;
}

NSString *DPWhyHiddenBy(DPPatch *disabler) {
    if (!DPShownOn(disabler)) return nil;
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPRequired(DPPatches[i]) == disabler && DPShownOn(DPPatches[i])) return nil;
    return [NSString stringWithFormat:@"Hidden while %@ is on", disabler->title];
}

NSString *DPWhyHidden(DPPatch *patch) { return DPShownOn(patch) ? DPWhyHiddenBy(DPPatchNamed(patch->disabledBy)) : nil; }

NSURL *DPWikiURL(DPPatch *patch) {
    if (DPIsLocalPatch(patch)) return nil;
    NSString *page = [patch->title stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    return [NSURL URLWithString:[@"https://github.com/JaceThings/DiaTweaks/wiki/" stringByAppendingString:page]];
}

NSArray<NSString *> *DPRelaunchingOnPause(void) {
    if (DPSafeMode || DPPausedAtLaunch) return @[];
    NSMutableArray<NSString *> *waiting = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        // App Icon and Morning Brief Language are baked into Dia, so pausing them needs a rebuild too.
        BOOL baked = [patch->key isEqualToString:@"appIcon"] || [patch->key isEqualToString:@"briefLanguage"];
        if ((patch->relaunch || baked) && patch->on) [waiting addObject:patch->title];
    }
    return waiting;
}

static BOOL DPResumingHandoff;

static BOOL DPNeedsRelaunchToResume(void) { return !DPPaused && DPPausedAtLaunch && !DPSafeMode; }

void DPSyncPauseRow(NSTextField *label, NSButton *button) {
    if (DPNeedsRelaunchToResume()) {
        label.stringValue = @"Tweaks will resume when Dia relaunches.";
        button.title = @"Relaunch";
        return;
    }
    label.stringValue = DPPaused ? @"Tweaks are paused, so none of them are running. Your settings are kept."
                                 : @"Pause every tweak and keep their settings.";
    if (!DPPaused) button.title = @"Pause Tweaks";
    else if (DPPausedAtLaunch && !DPSafeMode) button.title = @"Resume and Relaunch";
    else button.title = @"Resume Tweaks";
}

static void DPRelaunchToResume(void) {
    if (DPResumingHandoff) return;
    DPResumingHandoff = YES;
    DPPatch *icon = DPPatchNamed(@"appIcon");
    BOOL catalog = [NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"] isEqual:@"DiaChosenIcon"];
    if (icon && DPSavedOn(icon))
        return DPRunCLI(@[catalog ? @"set-icon" : @"build"], ^(NSString *output) {
            DPResumingHandoff = NO;
            DPHandOffAndQuit(@[@"apply"]);
        });
    DPResumingHandoff = NO;
    DPHandOffAndQuit(@[@"apply"]);
}

void DPSetTweaksPaused(BOOL paused, NSWindow *window) {
    if (DPNeedsRelaunchToResume()) return DPRelaunchToResume();
    if (DPPaused == paused || DPResumingHandoff) return;
    NSArray<NSString *> *waiting = paused ? DPRelaunchingOnPause() : @[];
    DPSetPaused(paused);
    if (!paused && DPPausedAtLaunch && !DPSafeMode) return DPRelaunchToResume();
    DPApplySavedSettings();
    if (!waiting.count || DPTesting) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Relaunch Dia to finish pausing?";
    alert.informativeText = [NSString stringWithFormat:@"%@ only %@ after a relaunch. Every other tweak is already off.",
                             [waiting componentsJoinedByString:@", "], waiting.count == 1 ? @"stops" : @"stop"];
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    DPPresentAlert(alert, window, ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"apply"]);
    });
}

@implementation DPPatchSwitch

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _hiddenIcon = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
    self.controlSize = NSControlSizeSmall;
    self.accessibilityLabel = patch->title;
    self.target = self;
    self.action = @selector(flip);
    [self sync];
    return self;
}

- (NSSize)intrinsicContentSize {
    static NSSize size;
    if (!size.width) size = [super intrinsicContentSize];
    return size;
}

- (void)flip {
    DPSetPatch(self.patch, self.state == NSControlStateValueOn, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

- (NSView *)withHiddenIcon {
    NSStackView *stack = [NSStackView new];
    stack.spacing = 8;
    stack.detachesHiddenViews = NO;  // Before adding the icon, which a stack drops if it's already hidden.
    [stack addArrangedSubview:self.hiddenIcon];
    [stack addArrangedSubview:self];
    return stack;
}

- (void)sync {
    self.state = DPShownOn(self.patch) ? NSControlStateValueOn : NSControlStateValueOff;
    self.enabled = !DPWhyDisabled(self.patch) && !DPPaused;
    NSString *hint = DPWhyHidden(self.patch);
    DPSetHint(self.hiddenIcon, hint);
    self.hiddenIcon.hidden = !hint;
}
@end
