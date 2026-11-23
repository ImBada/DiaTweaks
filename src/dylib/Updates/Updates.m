#import "Updates/Updates.h"
#include <sys/xattr.h>

NSString *const DPDia = @"dia", *const DPTweaks = @"tweaks";
NSNotificationName const DPUpdatesDidChangeNotification = @"DPUpdatesDidChange";

NSString *DPPartName(NSString *part) { return [part isEqual:DPDia] ? @"Dia" : @"DiaTweaks"; }

static NSArray<NSString *> *DPParts(void) {
    static NSArray<NSString *> *parts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ parts = @[ DPDia, DPTweaks ]; });
    return parts;
}

static NSString *DPSupport(NSString *name) {
    return [DPAppSupport(@"DiaPatches") stringByAppendingPathComponent:name];
}

static NSTask *DPCLITask(NSArray<NSString *> *args) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:DPSupport(@"bin/diapatch")];
    task.arguments = args;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    return task;
}

static BOOL DPLaunchCLI(NSArray<NSString *> *args) {
    NSTask *task = DPCLITask(args);
    task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    return [task launchAndReturnError:nil];
}

static NSDictionary *DPUpdateEntry(NSDictionary *found, NSString *part) {
    id entry = found[part];
    return [entry isKindOfClass:NSDictionary.class] ? entry : nil;
}

static NSUserDefaults *DPUpdateDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

BOOL DPIsLocalBuild(NSString *part) {
    return [part isEqual:DPTweaks] && ![[NSDictionary dictionaryWithContentsOfFile:DPSupport(@"release.plist")][@"tag"] isKindOfClass:NSString.class];
}

static NSString *DPAutoKey(NSString *part) { return [part isEqual:DPDia] ? @"autoUpdateDia" : @"autoUpdateTweaks"; }

DPAutoLevel DPAutoLevelOf(NSString *part) {
    id level = [DPUpdateDefaults() objectForKey:DPAutoKey(part)];
    return level ? MIN(MAX([level integerValue], DPAutoOff), DPAutoInstall) : DPAutoInstall;
}

void DPSetAutoLevel(NSString *part, DPAutoLevel level) { [DPUpdateDefaults() setInteger:level forKey:DPAutoKey(part)]; }

static NSString *DPReasonIn(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *line = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@"\n"].lastObject;
    if ([line hasPrefix:@"diapatch: "]) line = [line substringFromIndex:10];
    return line.length ? line : nil;
}

static BOOL DPHandedOff;

void DPRunCLIReporting(NSArray<NSString *> *args, void (^completion)(NSString *output, NSString *reason)) {
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_async(queue, ^{
        NSTask *task = DPCLITask(args);
        NSPipe *pipe = [NSPipe pipe], *errors = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = errors;
        NSString *output = nil, *reason = nil;
        NSError *launchError = nil;
        if ([task launchAndReturnError:&launchError]) {
            // Drain stderr concurrently so verbose child output can't fill the pipe buffer and deadlock stdout.
            __block NSData *errData = nil;
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_async(group, queue, ^{ errData = [errors.fileHandleForReading readDataToEndOfFile]; });
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
            [task waitUntilExit];
            if (task.terminationStatus == 0) output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            else reason = DPReasonIn(errData);
        } else {
            reason = launchError.localizedDescription;
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(output, reason); });
    });
}

void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) {
    DPRunCLIReporting(args, ^(NSString *output, NSString *reason) { if (completion) completion(output); });
}

void DPHandOffAndQuit(NSArray<NSString *> *args) {
    if (DPHandedOff) return;
    if (!DPLaunchCLI([args arrayByAddingObjectsFromArray:@[@"--wait", @(getpid()).stringValue, @"--relaunch"]])) return;
    DPHandedOff = YES;
    [NSApp terminate:nil];
}

@implementation DPUpdates {
    NSMutableDictionary<NSString *, NSMutableArray *> *_whenDownloaded;
    NSMutableArray *_checked, *_recheck;
    NSMutableDictionary<NSString *, NSString *> *_failed;
    NSString *_unpatchable;
    NSTimer *_progress;
    NSDictionary *_found;
    NSMutableDictionary<NSString *, id> *_pretend;
}

+ (instancetype)shared {
    static DPUpdates *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [DPUpdates new]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _whenDownloaded = [NSMutableDictionary new];
    _checked = [NSMutableArray new];
    _recheck = [NSMutableArray new];
    _failed = [NSMutableDictionary new];
    _pretend = [NSMutableDictionary new];
    return self;
}

- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:DPUpdatesDidChangeNotification object:self]; }

- (void)check:(void (^)(void))done {
    if (done) [_checked addObject:[done copy]];
    if (_checking) return;
    _checking = YES;
    [self changed];
    DPRunCLI(@[@"check", @"--json"], ^(NSString *output) {
        id raw = output ? [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        NSMutableDictionary *parsed = nil;
        if ([raw isKindOfClass:NSDictionary.class]) {
            parsed = [NSMutableDictionary new];
            for (NSString *part in DPParts()) {
                NSDictionary *entry = DPUpdateEntry(raw, part);
                if (entry) parsed[part] = entry;
            }
        }
        self->_found = parsed;
        for (NSString *part in DPParts())
            if ([self staged:part]) [self->_failed removeObjectForKey:part];
        NSString *unpatchable = DPUpdateEntry(self->_found, DPDia)[@"unpatchable"];
        if ([unpatchable isKindOfClass:NSString.class]) {
            if (!self->_failed[DPDia] && !self->_whenDownloaded[DPDia]) self->_failed[DPDia] = self->_unpatchable = unpatchable;
        } else if (self->_unpatchable && [self->_failed[DPDia] isEqualToString:self->_unpatchable]) {
            [self->_failed removeObjectForKey:DPDia];
            self->_unpatchable = nil;
        }
        self->_checking = NO;
        NSArray *waiting = [self->_checked copy];
        [self->_checked removeAllObjects];
        NSArray *recheck = self->_recheck.count ? [self->_recheck copy] : nil;
        [self->_recheck removeAllObjects];
        [self changed];
        for (void (^block)(void) in waiting) block();
        if (recheck) {
            [self->_checked addObjectsFromArray:recheck];
            [self check:nil];
        }
    });
}

- (NSDictionary *)found {
    if (!_pretend.count) return _found;
    NSMutableDictionary *found = [_found mutableCopy] ?: [NSMutableDictionary new];
    for (NSString *part in _pretend) {
        BOOL dia = [part isEqual:DPDia], staged = [_pretend[part] isEqual:@"staged"];
        NSString *latest = dia ? @"1.56.0 (90000)" : @"v1.1.0";
        NSMutableDictionary *entry = [DPUpdateEntry(found, part) ?: @{} mutableCopy];
        [entry addEntriesFromDictionary:@{
            @"latest" : latest, @"available" : @(!staged), @"staged" : staged ? latest : NSNull.null,
            @"size" : dia ? @704038560 : @960161,
            @"releaseNotes" : dia ? @"https://www.diabrowser.com/release-notes/latest" : @"https://github.com/JaceThings/DiaTweaks/releases",
        }];
        found[part] = entry;
    }
    return found;
}

- (NSString *)checkProblem {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSString *part in DPParts())
        if ([DPUpdateEntry(_found, part)[@"error"] isKindOfClass:NSString.class]) [names addObject:DPPartName(part)];
    if (names.count == 2) return @"Couldn’t check for updates";
    return names.count ? [NSString stringWithFormat:@"Couldn’t check for %@ updates", names[0]] : nil;
}

- (BOOL)available:(NSString *)part { return [DPUpdateEntry(self.found, part)[@"available"] boolValue]; }
- (BOOL)staged:(NSString *)part { return [DPUpdateEntry(self.found, part)[@"staged"] isKindOfClass:NSString.class]; }
- (BOOL)downloading:(NSString *)part { return _whenDownloaded[part] != nil; }
- (BOOL)failed:(NSString *)part { return _failed[part] != nil; }
- (NSString *)failure:(NSString *)part { return _failed[part].length ? _failed[part] : nil; }

- (double)progress:(NSString *)part {
    if ([_pretend[part] isKindOfClass:NSDate.class]) return MIN(-[_pretend[part] timeIntervalSinceNow] / 3, 1);
    static NSString *cacheDir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DiaPatches"];
    });
    NSString *file = [cacheDir stringByAppendingPathComponent:[part isEqual:DPDia] ? @"download/Dia.zip" : @"release/DiaTweaks.zip"];
    id rawSize = DPUpdateEntry(self.found, part)[@"size"];
    double size = [rawSize isKindOfClass:NSNumber.class] ? [rawSize doubleValue] : 0;
    double got = [[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil][NSFileSize] doubleValue];
    if (size > 0 && got < size) return got / size;
    return got > 0 ? -1 : 0;
}

- (void)download:(NSString *)part then:(void (^)(void))done {
    if (_whenDownloaded[part]) {
        if (done) [_whenDownloaded[part] addObject:[done copy]];
        return;
    }
    _whenDownloaded[part] = done ? [NSMutableArray arrayWithObject:[done copy]] : [NSMutableArray new];
    [_failed removeObjectForKey:part];
    if (!_progress) _progress = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *_) { [self tick]; }];
    [self changed];
    if (_pretend[part]) {
        _pretend[part] = NSDate.date;
        return;
    }
    DPRunCLIReporting(@[[part isEqual:DPDia] ? @"update" : @"self-update"], ^(NSString *output, NSString *reason) {
        if (!output) self->_failed[part] = reason ?: @"";
        [self finishDownload:part];
    });
}

- (void)stopTickingIfIdle {
    if (_whenDownloaded.count) return;
    [_progress invalidate];
    _progress = nil;
}

- (void)finishDownload:(NSString *)part {
    NSArray *waiting = _whenDownloaded[part];
    [_whenDownloaded removeObjectForKey:part];
    [self stopTickingIfIdle];
    if (_pretend[part]) {
        _pretend[part] = @"staged";
        [self changed];
        for (void (^block)(void) in waiting) block();
    } else {
        void (^notify)(void) = ^{ for (void (^block)(void) in waiting) block(); };
        // A check started before the download finished holds a stale snapshot, so schedule a fresh check after it.
        if (_checking) [_recheck addObject:[notify copy]];
        else [self check:notify];
    }
}

- (void)tick {
    for (NSString *part in _pretend.allKeys)
        if ([_pretend[part] isKindOfClass:NSDate.class] && [self progress:part] >= 1) [self finishDownload:part];
    [self changed];
}

- (void)installAndRelaunch:(NSArray<NSString *> *)parts {
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"apply"];
    for (NSString *part in parts) {
        if (_pretend[part]) [_pretend removeObjectForKey:part];
        else [args addObject:[part isEqual:DPDia] ? @"--dia" : @"--tweaks"];
    }
    if (args.count > 1) DPHandOffAndQuit(args);
    else [self changed];
}

- (void)pretend:(NSString *)part {
    _pretend[part] = @"available";
    [self changed];
}

- (void)stopPretending {
    for (NSString *part in _pretend.allKeys)
        if ([_pretend[part] isKindOfClass:NSDate.class]) [_whenDownloaded removeObjectForKey:part];
    [_pretend removeAllObjects];
    [self stopTickingIfIdle];
    [self changed];
}
@end

static void DPInstallDownloaded(DPUpdates *updates, NSArray<NSString *> *parts) {
    NSMutableArray<NSString *> *staged = [NSMutableArray new], *missing = [NSMutableArray new], *reasons = [NSMutableArray new];
    for (NSString *each in parts) {
        if ([updates staged:each]) {
            [staged addObject:each];
            continue;
        }
        [missing addObject:DPPartName(each)];
        NSString *reason = [updates failure:each];
        if (reason) [reasons addObject:reason];
    }
    if (staged.count) return [updates installAndRelaunch:staged];
    NSAlert *failed = [NSAlert new];
    failed.messageText = [@"Couldn’t download " stringByAppendingString:[missing componentsJoinedByString:@" and "]];
    failed.informativeText = [reasons componentsJoinedByString:@"\n"];
    [failed runModal];
}

static void DPShowUpdateAlert(void) {
    DPUpdates *updates = DPUpdates.shared;
    [updates check:^{
        NSMutableArray<NSString *> *parts = [NSMutableArray new], *names = [NSMutableArray new];
        for (NSString *part in DPParts()) {
            BOOL staged = [updates staged:part];
            if (!staged && ![updates available:part]) continue;
            [parts addObject:part];
            [names addObject:[NSString stringWithFormat:@"%@ %@", DPPartName(part), updates.found[part][staged ? @"staged" : @"latest"]]];
        }
        NSAlert *alert = [NSAlert new];
        if (!parts.count) {
            alert.messageText = !updates.found ? @"Couldn’t check for updates" : updates.checkProblem ?: @"Dia and DiaTweaks are up to date";
            [alert runModal];
            return;
        }
        alert.messageText = [[names componentsJoinedByString:@" and "] stringByAppendingString:@" available"];
        BOOL allStaged = YES;
        for (NSString *part in parts) allStaged &= [updates staged:part];
        BOOL many = parts.count > 1;
        NSString *what = many ? @"them" : @"it", *are = many ? @"they’re" : @"it’s";
        alert.informativeText = allStaged ? [NSString stringWithFormat:@"Dia relaunches to install %@.", what]
                                          : [NSString stringWithFormat:@"Dia relaunches to install %@ once %@ downloaded.", what, are];
        [alert addButtonWithTitle:@"Update and Relaunch"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        __block NSUInteger left = parts.count;
        void (^ready)(void) = ^{ if (--left == 0) DPInstallDownloaded(updates, parts); };
        for (NSString *part in parts) {
            if ([updates staged:part]) ready();
            else [updates download:part then:ready];
        }
    }];
}

static void DPInstallOnQuit(void) {
    if (DPHandedOff) return;
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL dia = DPAutoLevelOf(DPDia) == DPAutoInstall && [files fileExistsAtPath:DPSupport(@"staged/Dia.app")] && [files fileExistsAtPath:DPSupport(@"staged/ready")];
    BOOL tweaks = DPAutoLevelOf(DPTweaks) == DPAutoInstall && !DPIsLocalBuild(DPTweaks) && [files fileExistsAtPath:DPSupport(@"staged/DiaTweaks/release.plist")];
    if (!dia && !tweaks) return;
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"apply", @"--wait", @(getpid()).stringValue, nil];
    if (dia) [args addObject:@"--dia"];
    if (tweaks) [args addObject:@"--tweaks"];
    DPLaunchCLI(args);
}

@protocol DPSparkleUpdater <NSObject>
@property (nonatomic, readonly) NSURL *feedURL;
@end

static void DPSaveDiaFeed(id<DPSparkleUpdater> updater) {
    NSString *feed = [updater respondsToSelector:@selector(feedURL)] ? updater.feedURL.absoluteString : nil;
    if (feed) [DPUpdateDefaults() setObject:feed forKey:@"diaFeed"];
}

static BOOL DPUpdater_startUpdater(id self, SEL _cmd, NSError **error) {
    DPSaveDiaFeed(self);
    return DPCallOriginal(DPUpdater_startUpdater, self, error);
}

static void DPUpdater_checkForUpdates(id self, SEL _cmd) {
    DPSaveDiaFeed(self);
    DPShowUpdateAlert();
}

static void DPUpdater_checkForUpdatesInBackground(id self, SEL _cmd) {
    DPSaveDiaFeed(self);
}

// Sparkle's own schedule skips the hooks above, and Dia's "Automatically update Dia" can turn it on.
static BOOL DPUpdater_automaticallyChecksForUpdates(id self, SEL _cmd) { return NO; }

// Older diapatch runs from Dia left their files quarantined, so macOS won't run them.
static void DPLiftQuarantine(void) {
    for (NSString *name in @[ @"bin/diapatch", @"bin/diatweaks", @"DiaPatches.dylib", @"patches.json" ])
        removexattr(DPSupport(name).fileSystemRepresentation, "com.apple.quarantine", 0);
}

void DPInstallUpdates(void) {
    DPLiftQuarantine();
    DPHook("SPUUpdater", @selector(startUpdater:), (IMP)DPUpdater_startUpdater);
    DPHook("SPUUpdater", @selector(checkForUpdates), (IMP)DPUpdater_checkForUpdates);
    DPHook("SPUUpdater", @selector(checkForUpdatesInBackground), (IMP)DPUpdater_checkForUpdatesInBackground);
    DPHook("SPUUpdater", @selector(automaticallyChecksForUpdates), (IMP)DPUpdater_automaticallyChecksForUpdates);
    DPOnLaunch(^{
        DPOnMenuItem(nil, @"Check for Updates", ^{ DPShowUpdateAlert(); });
        if (DPAutoLevelOf(DPDia) == DPAutoOff && DPAutoLevelOf(DPTweaks) == DPAutoOff) return;
        DPUpdates *updates = DPUpdates.shared;
        [updates check:^{
            for (NSString *part in DPParts())
                if (DPAutoLevelOf(part) >= DPAutoDownload && !DPIsLocalBuild(part) && [updates available:part] && ![updates failed:part])
                    [updates download:part then:nil];
        }];
    });
    DPOnQuit(^{ DPInstallOnQuit(); });
}
