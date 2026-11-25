#import "SafeMode/SafeMode.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

// Long on purpose: patches often crash only on a first resize or new tab.
static const int64_t DPSurviveSeconds = 180;

NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
static NSURL *DPStateURL, *DPPauseURL;
static NSMutableDictionary *DPState;

static void DPMakeFolder(void) {
    [NSFileManager.defaultManager createDirectoryAtURL:DPStateURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
}

static void DPSaveState(void) {
    if (!DPState || !DPStateURL) return;
    DPMakeFolder();
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:DPState format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    [plist writeToURL:DPStateURL options:NSDataWritingAtomic error:nil];
}

BOOL DPPauseSaved(void) { return [NSFileManager.defaultManager fileExistsAtPath:DPPauseURL.path]; }

BOOL DPLocalSafeModeOff(void) { return [DPState[@"localOff"] boolValue]; }

void DPSetLocalSafeModeOff(BOOL off) {
    if (!DPState) return;
    if (off) DPState[@"localOff"] = @YES;
    else [DPState removeObjectForKey:@"localOff"];
    DPSaveState();
}

// Local.m owns the folder, but this file is linked on its own in tests, so resolve the path here.
static BOOL DPLocalFolderHasTweaks(void) {
    const char *home = getenv("DIAPATCH_HOME");
    NSString *base = home && *home ? @(home)
                                   : [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                                         stringByAppendingPathComponent:@"DiaPatches"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[base stringByAppendingPathComponent:@"local"] error:NULL])
        if (![name hasPrefix:@"."] && ![name isEqual:@"README.md"]) return YES;
    return NO;
}

void DPSetPaused(BOOL paused) {
    DPPaused = paused;
    if (!DPPauseURL) return;
    if (paused) {
        DPMakeFolder();
        [NSData.data writeToURL:DPPauseURL options:NSDataWritingAtomic error:nil];
    } else [NSFileManager.defaultManager removeItemAtURL:DPPauseURL error:nil];
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

static BOOL DPReportHasPid(NSURL *report, NSArray<NSData *> *needles) {
    NSData *head = [[NSFileHandle fileHandleForReadingFromURL:report error:nil] readDataUpToLength:64 * 1024 error:nil];
    for (NSData *needle in needles)
        if ([head rangeOfData:needle options:0 range:NSMakeRange(0, head.length)].location != NSNotFound) return YES;
    return NO;
}

static BOOL DPCrashed(NSDictionary *state) {
    NSDate *launched = state[@"launched"];
    if (![launched isKindOfClass:NSDate.class]) return YES;
    NSNumber *pid = state[@"pid"];
    if (![pid isKindOfClass:NSNumber.class]) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *prefix = [NSProcessInfo.processInfo.processName stringByAppendingString:@"-"];
    NSArray<NSData *> *needles = @[ [[NSString stringWithFormat:@"\"pid\" : %@,", pid] dataUsingEncoding:NSUTF8StringEncoding],
                                    [[NSString stringWithFormat:@"\"pid\":%@,", pid] dataUsingEncoding:NSUTF8StringEncoding] ];
    NSURL *reports = [files.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
    for (NSURL *url in [files contentsOfDirectoryAtURL:reports includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
        if (![url.lastPathComponent hasPrefix:prefix] || ![url.pathExtension isEqual:@"ips"]) continue;
        NSDate *modified = nil;
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        if ([modified isKindOfClass:NSDate.class] && [modified compare:launched] != NSOrderedAscending && DPReportHasPid(url, needles)) return YES;
    }
    return NO;
}

static void DPSurvived(void) {
    if (DPPausedAtLaunch || ![DPState[@"launching"] boolValue]) return;
    // A newer relaunch may already own safe-mode.plist.
    NSNumber *owner = [NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil][@"pid"];
    if (![owner isKindOfClass:NSNumber.class] || owner.intValue != getpid()) return;
    DPState[@"launching"] = @NO;
    // Level 2 skips Settings, so one clean launch steps down to 1 once per build.
    if (DPSafeMode == 2 && ![DPState[@"steppedDown"] boolValue]) {
        DPState[@"level"] = @1;
        DPState[@"steppedDown"] = @YES;
    }
    DPSaveState();
}

static NSMutableDictionary *DPLoadState(NSString *build) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil];
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObject:build forKey:@"build"];
    if (![saved[@"build"] isEqual:build]) return state;
    for (NSString *key in @[ @"level", @"crashes", @"launching", @"steppedDown", @"localOff", @"pid" ])
        if ([saved[key] isKindOfClass:NSNumber.class]) state[key] = saved[key];
    if ([saved[@"launched"] isKindOfClass:NSDate.class]) state[@"launched"] = saved[@"launched"];
    return state;
}

void DPBeginLaunch(void) {
    if (DPIsChildProcess()) return;
    Dl_info info = { 0 };
    if (!dladdr((const void *)DPBeginLaunch, &info) || !info.dli_fname || !info.dli_fbase) return;
    DPStateURL = [NSURL fileURLWithPath:[@(info.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"safe-mode.plist"]];
    DPPauseURL = [DPStateURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"paused"];
    DPPaused = DPPausedAtLaunch = DPPauseSaved();
    NSString *build = DPBuildUUID(info.dli_fbase);
    DPState = DPLoadState(build);
    DPSafeMode = MIN(MAX([DPState[@"level"] integerValue], 0), 2);
    DPOnQuit(^{ DPSurvived(); });
    // Crashes while paused neither count toward nor reset safe mode.
    if (DPPaused) return;
    NSInteger crashes = [DPState[@"crashes"] integerValue];
    if ([DPState[@"launching"] boolValue]) crashes += DPCrashed(DPState);
    else crashes = 0;
    if (crashes >= 2) {
        // Try the user's own tweaks alone first: dropping 100 official ones to fix one local file is a bad trade.
        if (![DPState[@"localOff"] boolValue] && DPLocalFolderHasTweaks()) {
            DPState[@"localOff"] = @YES;
            crashes = 0;
        } else if (DPSafeMode < 2) {
            DPSafeMode++;
            crashes = 0;
        }
    }
    [DPState addEntriesFromDictionary:@{@"level": @(DPSafeMode), @"crashes": @(crashes), @"launching": @YES, @"launched": NSDate.date, @"pid": @(getpid())}];
    DPSaveState();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPSurviveSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSurvived(); });
}

void DPLeaveSafeMode(void) {
    DPState = [NSMutableDictionary dictionaryWithObject:DPState[@"build"] ?: @"" forKey:@"build"];
    DPSaveState();
}
