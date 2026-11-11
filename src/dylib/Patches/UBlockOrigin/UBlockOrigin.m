#import "UBlockOrigin.h"
#import "Updates/Updates.h"

// Loads uBlock Origin, a Manifest V2 extension, after ExtensionChecks.m lets Chromium run it. Chromium reads the
// folder once as Dia starts, so a newer version waits in DPUBlockStaged until then.

static NSString *const kNativeAdBlock = @"nativeAdBlockEnabled";  // Dia's own Block Ads switch
static NSString *const kLastCheck = @"uBlockOriginLastCheck";
static BOOL gLoaded, gLiftFailed, gFetching, gOffered;

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

// Dia's ad blocker is turned off only in this Dia's memory, in the argument domain that overrides what Dia saved.
// Nothing needs putting back, so after a crash, in safe mode and in the original Dia it's as the user set it.
static void DPSetNativeAdBlockOff(BOOL off) {
    NSUserDefaults *dia = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *arguments = [[dia volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([arguments[kNativeAdBlock] isEqual:@NO] == off) return;
    if (off) arguments[kNativeAdBlock] = @NO;
    else [arguments removeObjectForKey:kNativeAdBlock];
    [dia setVolatileDomain:arguments forName:NSArgumentDomain];
}

// Replaces the folder in one step, so a failed move keeps the version that was there.
static void DPSwapInStaged(void) {
    if (gLoaded || !DPUBlockVersion(DPUBlockStaged())) return;
    NSURL *folder = [NSURL fileURLWithPath:DPUBlockFolder()], *staged = [NSURL fileURLWithPath:DPUBlockStaged()];
    NSError *error;
    BOOL swapped = [NSFileManager.defaultManager fileExistsAtPath:folder.path]
        ? [NSFileManager.defaultManager replaceItemAtURL:folder withItemAtURL:staged backupItemName:nil options:0 resultingItemURL:nil error:&error]
        : [NSFileManager.defaultManager moveItemAtURL:staged toURL:folder error:&error];
    if (!swapped) NSLog(@"DiaPatches: couldn’t move the new uBlock Origin into place: %@", error.localizedDescription);
}

static void DPCheckForUpdate(void) {
    NSDate *last = [DPSettings() objectForKey:kLastCheck];
    if (gFetching || !DPUBlockOrigin.on || ([last isKindOfClass:NSDate.class] && -last.timeIntervalSinceNow < 24 * 60 * 60)) return;
    gFetching = YES;
    DPFetchUBlock(^(NSString *problem) {
        gFetching = NO;
        if (problem) NSLog(@"DiaPatches: couldn’t update uBlock Origin: %@", problem);
        else [DPSettings() setObject:NSDate.date forKey:kLastCheck];
    });
}

static void DPOfferRelaunch(BOOL on) {
    if (DPTesting) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = on ? @"Relaunch Dia to block ads with uBlock Origin" : @"Relaunch Dia to remove uBlock Origin";
    alert.informativeText = on ? @"Until then, Dia’s own ad blocker keeps working." : @"Until then, uBlock Origin keeps blocking ads.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

static void DPTurnOff(DPPatch *patch, NSString *title, NSString *problem) {
    DPSetPatch(patch, NO, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = problem;
    [alert runModal];
}

static NSString *const kCantRun = @"This Dia can’t run uBlock Origin";

// Downloads it if it isn't here yet, then offers once to relaunch Dia into it. A download the user didn't just ask
// for, as Dia opens, waits for the next try instead of turning the switch off.
static void DPGetReady(DPPatch *patch, BOOL asked) {
    if (gFetching || DPTesting) return;
    if (!DPFindExtensionChecks())
        return DPTurnOff(patch, kCantRun, @"Chromium’s extension checks aren’t where DiaTweaks looks for them. A DiaTweaks update may fix it.");
    gFetching = YES;
    DPFetchUBlock(^(NSString *problem) {
        gFetching = NO;
        if (!patch->on) return;
        DPSwapInStaged();
        if (DPUBlockVersion(DPUBlockFolder())) {
            if (!gOffered || asked) gOffered = YES, DPOfferRelaunch(YES);
        } else if (asked) {
            DPTurnOff(patch, @"Couldn’t download uBlock Origin", problem ?: @"It isn’t where DiaTweaks put it.");
        } else {
            NSLog(@"DiaPatches: couldn’t download uBlock Origin, trying again later: %@", problem);
        }
    });
}

static void DPTick(void) {
    if (!DPUBlockOrigin.on) return;
    if (gLoaded) DPCheckForUpdate();
    else DPGetReady(&DPUBlockOrigin, NO);
}

static void DPInstallUBlockOrigin(void) {
    // The folder stays: once uBlock Origin has reloaded itself, Chromium remembers it as unpacked and would report it
    // missing at every launch. Without the checks lifted, Chromium keeps it off as a Manifest V2 extension.
    if (!DPUBlockOrigin.on) return (void)[NSFileManager.defaultManager removeItemAtPath:DPUBlockStaged() error:nil];
    DPSwapInStaged();
    if (DPUBlockVersion(DPUBlockFolder())) {
        gLoaded = DPLiftExtensionChecks();
        gLiftFailed = !gLoaded;
    }
    if (gLoaded) {
        DPLoadExtension(DPUBlockFolder());
        DPSetNativeAdBlockOff(YES);
    }
    DPOnLaunch(^{
        if (gLiftFailed) return DPTurnOff(&DPUBlockOrigin, kCantRun, @"Chromium’s extension checks couldn’t be changed, so it would stay off.");
        DPTick();
        [NSTimer scheduledTimerWithTimeInterval:60 * 60 repeats:YES block:^(NSTimer *_) { DPTick(); }];
    });
}

static void DPApplyUBlockOrigin(DPPatch *patch) {
    if (patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    DPSetNativeAdBlockOff(patch->on && gLoaded);
    if (patch->on && !gLoaded) DPGetReady(patch, YES);
    else if (!patch->on && gLoaded) DPOfferRelaunch(NO);
}

DP_PATCH(DPUBlockOrigin) {
    .key = @"uBlockOrigin",
    .order = 118,
    .section = @"Ad Blocking",
    .title = @"Block Ads with uBlock Origin",
    .detail = @"Block ads with the full uBlock Origin instead of Dia’s ad blocker, in every profile. Lets Manifest V2 extensions run again, which Chromium no longer allows. Downloaded from uBlock Origin’s GitHub and kept up to date. May need an update after some Dia releases.",
    .symbol = @"shield.lefthalf.filled",
    .tint = @"systemRedColor",
    .install = DPInstallUBlockOrigin,
    .apply = DPApplyUBlockOrigin,
};
