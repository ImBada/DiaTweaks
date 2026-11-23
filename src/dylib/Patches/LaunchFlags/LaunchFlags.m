#import "LaunchFlags.h"
#import "SafeMode/SafeMode.h"
#import "Updates/Updates.h"

static NSString *const DPArgsKey = @"launchFlagsArgs";
static NSString *const DPAppliedKey = @"launchFlagsApplied";
static NSArray<NSString *> *gLaunchedFlags;

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

NSString *DPLaunchFlagsSavedText(void) {
    id raw = [DPSettings() objectForKey:DPArgsKey];
    if ([raw isKindOfClass:NSString.class]) return raw;
    if ([raw isKindOfClass:NSArray.class]) return DPFormatLaunchFlagsArray(raw);
    return @"";
}

void DPLaunchFlagsSaveText(NSString *text) {
    if (text.length) [DPSettings() setObject:text forKey:DPArgsKey];
    else [DPSettings() removeObjectForKey:DPArgsKey];
}

NSArray<NSString *> *DPLaunchFlagsLaunched(void) { return gLaunchedFlags ?: @[]; }

static NSArray<NSString *> *DPPreviouslyApplied(void) {
    NSArray *saved = [DPSettings() arrayForKey:DPAppliedKey];
    if (!saved.count) return @[];
    NSMutableArray<NSString *> *flags = [NSMutableArray arrayWithCapacity:saved.count];
    for (id item in saved)
        if ([item isKindOfClass:NSString.class] && [item length]) [flags addObject:item];
    return flags;
}

void DPDropStaleLaunchFlags(void) {
    NSArray<NSString *> *previous = DPPreviouslyApplied();
    if (!previous.count) return;
    for (NSString *flag in previous) DPDropLaunchFlag(flag);
    [DPSettings() removeObjectForKey:DPAppliedKey];
}

static void DPInstallLaunchFlags(void) {
    gLaunchedFlags = @[];
    if (!DPLaunchFlags.on || DPPaused || DPSafeMode) {
        if (!DPSafeMode) DPDropStaleLaunchFlags();
        return;
    }
    NSArray<NSString *> *previous = DPPreviouslyApplied();
    NSArray<NSString *> *flags = DPParseLaunchFlags(DPLaunchFlagsSavedText(), nil, nil);
    for (NSString *flag in previous) DPDropLaunchFlag(flag);
    for (NSString *flag in flags) DPAddLaunchFlag(flag);
    gLaunchedFlags = flags;
    if (flags.count) [DPSettings() setObject:flags forKey:DPAppliedKey];
    else if (previous.count) [DPSettings() removeObjectForKey:DPAppliedKey];
}

static void DPApplyLaunchFlags(DPPatch *patch) {
    NSArray<NSString *> *wanted = patch->on ? DPParseLaunchFlags(DPLaunchFlagsSavedText(), nil, nil) : @[];
    if (DPTesting || [wanted isEqual:DPLaunchFlagsLaunched()] || patch->on != DPSavedOn(patch)) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to apply your launch flags" : @"Relaunch Dia to remove your launch flags";
    alert.informativeText = @"Until then, Dia keeps running with the flags it opened with.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPLaunchFlags) {
    .key = @"launchFlags",
    .order = 99,
    .title = @"Launch Flags",
    .detail = @"Pass extra Chromium flags whenever Dia opens, whether from the Dock, a launcher, a link, or a relaunch. Useful for flags like --force-renderer-accessibility=complete. Relaunch Dia after changing flags.",
    .symbol = @"terminal.fill",
    .tint = @"systemYellowColor",
    .section = @"App",
    .classes = DPClasses(DPDiaAppConfiguration),
    .relaunch = YES,
    .rows = DPLaunchFlagsRows,
    .install = DPInstallLaunchFlags,
    .apply = DPApplyLaunchFlags,
};
