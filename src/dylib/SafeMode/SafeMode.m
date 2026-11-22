#import "SafeMode/SafeMode.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

// Long on purpose: patches often crash only on a first resize or new tab.
static const int64_t DPSurviveSeconds = 180;

NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
static NSURL *DPStateURL, *DPPauseURL;
static NSMutableDictionary *DPState;

BOOL DPPauseSaved(void) { return [NSFileManager.defaultManager fileExistsAtPath:DPPauseURL.path]; }

void DPSetPaused(BOOL paused) {
    DPPaused = paused;
    if (paused) [NSData.data writeToFile:DPPauseURL.path atomically:YES];
    else [NSFileManager.defaultManager removeItemAtURL:DPPauseURL error:nil];
}

BOOL DPIsChildProcess(void) {
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSString *name = process.processName;
    if ([name hasPrefix:@"Dia Helper"] || [name isEqualToString:@"chrome_crashpad_handler"]) return YES;
    NSArray<NSString *> *args = process.arguments;
    for (NSUInteger i = 1; i < args.count; i++)
        if ([args[i] hasPrefix:@"--type="] || [args[i] hasPrefix:@"--utility-sub-type="]) return YES;
    return NO;
}

static NSString *DPBuildUUID(const struct mach_header_64 *header) {
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const uint8_t *)command + command->cmdsize))
        if (command->cmd == LC_UUID) return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
    return @"";
}

static BOOL DPCrashed(NSDictionary *state) {
    NSDate *launched = state[@"launched"];
    if (![launched isKindOfClass:NSDate.class]) return YES;
    NSNumber *pidNum = state[@"pid"];
    if (![pidNum isKindOfClass:NSNumber.class]) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *prefix = [NSProcessInfo.processInfo.processName stringByAppendingString:@"-"];
    NSString *pidSpaced = [NSString stringWithFormat:@"\"pid\" : %@,", pidNum];
    NSString *pidCompact = [NSString stringWithFormat:@"\"pid\":%@,", pidNum];
    NSURL *reports = [files.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
    for (NSURL *url in [files contentsOfDirectoryAtURL:reports includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
        if (![url.lastPathComponent hasPrefix:prefix] || ![url.pathExtension isEqual:@"ips"]) continue;
        NSDate *modified = nil;
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        if (![modified isKindOfClass:NSDate.class] || [modified compare:launched] == NSOrderedAscending) continue;
        NSString *contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if ([contents containsString:pidSpaced] || [contents containsString:pidCompact]) return YES;
    }
    return NO;
}

static void DPSurvived(void) {
    if (DPPausedAtLaunch || ![DPState[@"launching"] boolValue]) return;
    // A newer relaunch may already own safe-mode.plist.
    if ([[NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil][@"pid"] integerValue] != getpid()) return;
    DPState[@"launching"] = @NO;
    // Level 2 skips Settings, so one clean launch steps down to 1 once per build.
    if (DPSafeMode == 2 && ![DPState[@"steppedDown"] boolValue]) {
        DPState[@"level"] = @1;
        DPState[@"steppedDown"] = @YES;
    }
    [DPState writeToURL:DPStateURL error:nil];
}

void DPBeginLaunch(void) {
    if (DPIsChildProcess()) return;
    Dl_info info = { 0 };
    if (!dladdr((const void *)DPBeginLaunch, &info) || !info.dli_fname || !info.dli_fbase) return;
    DPStateURL = [NSURL fileURLWithPath:[@(info.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"safe-mode.plist"]];
    DPPauseURL = [DPStateURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"paused"];
    DPPaused = DPPausedAtLaunch = DPPauseSaved();
    NSString *build = DPBuildUUID(info.dli_fbase);
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil];
    DPState = [saved[@"build"] isEqual:build] ? [saved mutableCopy] : [NSMutableDictionary dictionaryWithObject:build forKey:@"build"];
    DPSafeMode = MIN(MAX([DPState[@"level"] integerValue], 0), 2);
    DPOnQuit(^{ DPSurvived(); });
    // Crashes while paused neither count toward nor reset safe mode.
    if (DPPaused) return;
    NSInteger crashes = [DPState[@"crashes"] integerValue];
    if ([DPState[@"launching"] boolValue]) crashes += DPCrashed(DPState);
    else crashes = 0;
    if (crashes >= 2 && DPSafeMode < 2) DPSafeMode++, crashes = 0;
    [DPState addEntriesFromDictionary:@{@"level": @(DPSafeMode), @"crashes": @(crashes), @"launching": @YES, @"launched": NSDate.date, @"pid": @(getpid())}];
    [DPState writeToURL:DPStateURL error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPSurviveSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSurvived(); });
}

void DPLeaveSafeMode(void) {
    DPState = [NSMutableDictionary dictionaryWithObject:DPState[@"build"] ?: @"" forKey:@"build"];
    [DPState writeToURL:DPStateURL error:nil];
}
