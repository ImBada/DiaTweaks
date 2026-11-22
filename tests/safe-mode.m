#import <dlfcn.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "StdPatch/StdPatch.h"

static const char *DPTestDylib;
static int DPTestDladdr(const void *address, Dl_info *info) {
    int found = dladdr(address, info);
    info->dli_fname = DPTestDylib;
    return found;
}
#define dladdr DPTestDladdr

static void (^DPQuit)(void);
void DPOnQuit(void (^block)(void)) { DPQuit = [block copy]; }

#import "SafeMode/SafeMode.m"

static void child(const char *support, const char *home) {
    @autoreleasepool {
        NSURL *reports = [NSURL fileURLWithPath:@(home)];
        class_replaceMethod(NSFileManager.class, @selector(homeDirectoryForCurrentUser), imp_implementationWithBlock(^NSURL *(id self) { return reports; }), "@@:");
        DPTestDylib = [[@(support) stringByAppendingPathComponent:@"DiaPatches.dylib"] fileSystemRepresentation];
        DPBeginLaunch();
        printf("level %ld paused %d\n", (long)DPSafeMode, DPPaused);
        fflush(stdout);
        char command[16] = "";
        if (fgets(command, sizeof command, stdin) && !strncmp(command, "quit", 4)) DPQuit();
        printf("done\n");
        fflush(stdout);
        _exit(0);
    }
}

@interface DPLaunch : NSObject
@property NSTask *task;
@property NSFileHandle *input, *output;
@property NSInteger level;
@property BOOL paused;
@end
@implementation DPLaunch
- (NSString *)line {
    NSMutableData *line = [NSMutableData data];
    for (NSData *byte = [self.output readDataOfLength:1]; byte.length && *(const char *)byte.bytes != '\n'; byte = [self.output readDataOfLength:1]) [line appendData:byte];
    return [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
}
- (void)end:(NSString *)command {
    [self.input writeData:[[command stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [self line];
    [self.task waitUntilExit];
}
@end

static NSString *support, *home;
static int failures;

static DPLaunch *launchWithArgs(NSArray<NSString *> *extra) {
    DPLaunch *launch = [DPLaunch new];
    NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe];
    launch.task = [NSTask new];
    launch.task.executableURL = [NSURL fileURLWithPath:NSBundle.mainBundle.executablePath];
    launch.task.arguments = [@[ @"child", support, home ] arrayByAddingObjectsFromArray:extra];
    launch.task.standardInput = in;
    launch.task.standardOutput = out;
    launch.input = in.fileHandleForWriting;
    launch.output = out.fileHandleForReading;
    [launch.task launchAndReturnError:nil];
    NSString *line = [launch line];
    launch.level = [[line substringFromIndex:6] integerValue];
    launch.paused = [line containsString:@"paused 1"];
    return launch;
}

static DPLaunch *launch(void) { return launchWithArgs(@[]); }

static NSDictionary *state(void) { return [NSDictionary dictionaryWithContentsOfFile:[support stringByAppendingPathComponent:@"safe-mode.plist"]]; }

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void leaveCrashed(DPLaunch *launch) {
    [launch end:@"crash"];
    NSString *folder = [home stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *report = [NSString stringWithFormat:@"%@-%d.ips", NSProcessInfo.processInfo.processName, launch.task.processIdentifier];
    [[NSString stringWithFormat:@"{\n  \"pid\" : %d,\n}\n", launch.task.processIdentifier] writeToFile:[folder stringByAppendingPathComponent:report] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

int main(int argc, const char *argv[]) {
    if (argc >= 4 && !strcmp(argv[1], "child")) child(argv[2], argv[3]);
    @autoreleasepool {
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        support = [temporary stringByAppendingPathComponent:@"support"];
        home = [temporary stringByAppendingPathComponent:@"home"];
        [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];

        DPLaunch *first = launch();
        expect([state()[@"launching"] boolValue] && [state()[@"pid"] intValue] == first.task.processIdentifier, @"a launch marks the file with its pid");
        [first end:@"quit"];
        expect(![state()[@"launching"] boolValue], @"a launch that quits clears the marker");

        DPLaunch *old = launch(), *relaunched = launch();
        [old end:@"quit"];
        expect([state()[@"launching"] boolValue] && [state()[@"pid"] intValue] == relaunched.task.processIdentifier, @"the old process leaves the new process's marker alone");
        leaveCrashed(relaunched);
        DPLaunch *next = launch(), *again = launch();
        expect([state()[@"crashes"] integerValue] == 1, @"the crash of the relaunched Dia is counted");
        [next end:@"quit"];
        leaveCrashed(again);
        DPLaunch *last = launch();
        expect(last.level == 1, @"two crashes of relaunched Dias turn safe mode on");
        [last end:@"quit"];

        NSString *pause = [support stringByAppendingPathComponent:@"paused"];
        [NSData.data writeToFile:pause atomically:YES];
        DPLaunch *paused = launch();
        expect(paused.paused, @"a launch with the pause file reports paused");
        leaveCrashed(paused);
        DPLaunch *stillPaused = launch();
        expect(stillPaused.paused, @"a crash while paused leaves the pause alone");
        expect([state()[@"crashes"] integerValue] == 0, @"a crash while paused isn't counted");
        [stillPaused end:@"quit"];
        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPLaunch *resumed = launch();
        expect(!resumed.paused, @"removing the pause file resumes");
        [resumed end:@"quit"];

        // A crash while paused must not be counted when the next launch resumes unpaused.
        [NSData.data writeToFile:pause atomically:YES];
        DPLaunch *pausedCrash = launch();
        leaveCrashed(pausedCrash);
        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPLaunch *afterPausedCrash = launch();
        expect(!afterPausedCrash.paused && [state()[@"crashes"] integerValue] == 0 && afterPausedCrash.level == 1,
               @"a crash while paused is not counted on the next unpaused launch");
        [afterPausedCrash end:@"quit"];

        // A clean paused launch must neither erase a prior unpaused crash nor step down level 2.
        DPLaunch *unpausedCrash = launch();
        leaveCrashed(unpausedCrash);
        [NSData.data writeToFile:pause atomically:YES];
        DPLaunch *cleanPaused = launch();
        [cleanPaused end:@"quit"];
        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPLaunch *afterCleanPaused = launch();
        expect([state()[@"crashes"] integerValue] == 1, @"a clean paused launch preserves a prior unpaused crash");
        [afterCleanPaused end:@"quit"];

        NSMutableDictionary *levelTwo = [state() mutableCopy];
        levelTwo[@"level"] = @2;
        levelTwo[@"steppedDown"] = @NO;
        levelTwo[@"launching"] = @NO;
        [levelTwo writeToFile:[support stringByAppendingPathComponent:@"safe-mode.plist"] atomically:YES];
        [NSData.data writeToFile:pause atomically:YES];
        DPLaunch *pausedL2 = launch();
        expect(pausedL2.level == 2, @"paused launch preserves level 2");
        [pausedL2 end:@"quit"];
        expect([state()[@"level"] integerValue] == 2, @"a clean paused launch does not step down level 2");
        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];

        // Chromium helper child processes (--type=renderer / gpu-process / utility) must never touch safe-mode.plist.
        [NSFileManager.defaultManager removeItemAtPath:[support stringByAppendingPathComponent:@"safe-mode.plist"] error:nil];
        DPLaunch *browser = launch();
        pid_t browserPid = browser.task.processIdentifier;
        for (NSString *flag in @[ @"--type=renderer", @"--type=gpu-process", @"--type=utility", @"--utility-sub-type=network.mojom.NetworkService" ]) {
            DPLaunch *helper = launchWithArgs(@[ flag ]);
            expect(helper.level == 0, [NSString stringWithFormat:@"child %@ leaves DPSafeMode at 0", flag]);
            leaveCrashed(helper);
        }
        expect([state()[@"pid"] intValue] == browserPid && [state()[@"crashes"] integerValue] == 0 && [state()[@"level"] integerValue] == 0,
               @"crashed Chromium child processes never overwrite browser pid or increment SafeMode crashes");
        [browser end:@"quit"];
        expect(![state()[@"launching"] boolValue], @"browser still clears launching marker cleanly after child helper exits");

        // Corrupt safe-mode.plist types (non-NSDate launched, out-of-range level) never crash and clamp level.
        NSMutableDictionary *corrupt = [state() mutableCopy];
        corrupt[@"launching"] = @YES;
        corrupt[@"launched"] = @"not-a-date";
        corrupt[@"pid"] = @"not-a-pid";
        corrupt[@"level"] = @(-5);
        [corrupt writeToFile:[support stringByAppendingPathComponent:@"safe-mode.plist"] atomically:YES];
        DPLaunch *afterCorrupt = launch();
        expect(afterCorrupt.level == 0, @"corrupt negative level and non-NSDate launched handled cleanly without crashing");
        [afterCorrupt end:@"quit"];

        // Compact JSON ("pid":123,) in .ips crash report is detected as a crash too.
        DPLaunch *compactCrash = launch();
        [compactCrash end:@"crash"];
        NSString *folder = [home stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *compactReport = [NSString stringWithFormat:@"%@-compact-%d.ips", NSProcessInfo.processInfo.processName, compactCrash.task.processIdentifier];
        [[NSString stringWithFormat:@"{\"pid\":%d,\"other\":1}\n", compactCrash.task.processIdentifier]
            writeToFile:[folder stringByAppendingPathComponent:compactReport] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        DPLaunch *afterCompact = launch();
        expect([state()[@"crashes"] integerValue] == 1, @"compact .ips pid format is counted as a crash");
        [afterCompact end:@"quit"];

        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
    }
    if (!failures) printf("all launch guard checks passed\n");
    return failures ? 1 : 0;
}
