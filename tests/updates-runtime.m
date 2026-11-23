#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import "Settings/Settings.h"

static NSString *DPTestSupport;
static NSMutableArray<NSArray<NSString *> *> *DPLaunchedArgs;
static int DPTerminateCount;

NSString *DPAppSupport(NSString *path) { return [DPTestSupport stringByAppendingPathComponent:path]; }
void DPOnLaunch(void (^block)(void)) {}
void DPOnQuit(void (^block)(void)) {}
void DPOnMenuItem(NSString *menu, NSString *titlePrefix, void (^action)(void)) {}
void DPHook(const char *className, SEL sel, IMP replacement) {}
IMP DPOriginalIMP(id object, SEL sel, IMP replacement) { return NULL; }
IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame) { return NULL; }
void DPPopOriginalIMP(DPHookFrame *frame) {}
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
NSString *DPWhyDisabled(DPPatch *patch) { return nil; }
NSString *DPWhyHidden(DPPatch *patch) { return nil; }
NSString *DPWhyHiddenBy(DPPatch *disabler) { return nil; }
DPPatch *DPRequired(DPPatch *patch) { return nil; }
DPPatch *DPPatchNamed(NSString *key) { return nil; }
DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;

@interface NSApplication (DPTestTerminate)
- (void)dp_testTerminate:(id)sender;
@end
@implementation NSApplication (DPTestTerminate)
- (void)dp_testTerminate:(id)sender { DPTerminateCount++; }
@end

static NSString *DPTestDomain(void) { return [NSString stringWithFormat:@"com.diapatches.updates-test.%d", getpid()]; }

@interface NSUserDefaults (DPUpdatesTest)
- (instancetype)dp_updatesInitWithSuiteName:(NSString *)suite;
@end
@implementation NSUserDefaults (DPUpdatesTest)
- (instancetype)dp_updatesInitWithSuiteName:(NSString *)suite {
    return [self dp_updatesInitWithSuiteName:[suite isEqual:@"com.diapatches"] ? DPTestDomain() : suite];
}
@end

#import "Updates/Updates.m"
#import "Settings/Controls.m"
#import "Settings/SoftwareUpdate.m"

static int failures;
static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void pumpUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void writeStubCLI(NSString *path, NSString *script) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(path.fileSystemRepresentation, 0755);
}

static BOOL hasLabelText(NSView *root, NSString *needle) {
    return DPFindView(root, ^BOOL(NSView *v) {
        return [v isKindOfClass:NSTextField.class] && [((NSTextField *)v).stringValue containsString:needle];
    }) != nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        method_exchangeImplementations(class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:)),
                                       class_getInstanceMethod(NSUserDefaults.class, @selector(dp_updatesInitWithSuiteName:)));
        method_exchangeImplementations(class_getInstanceMethod(NSApplication.class, @selector(terminate:)),
                                       class_getInstanceMethod(NSApplication.class, @selector(dp_testTerminate:)));

        NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        DPTestSupport = temp;
        NSString *cli = DPSupport(@"bin/diapatch");
        NSString *flagFile = [temp stringByAppendingPathComponent:@"staged.flag"];
        NSString *gateFile = [temp stringByAppendingPathComponent:@"gate.flag"];
        NSString *unpatchFile = [temp stringByAppendingPathComponent:@"unpatch.flag"];
        NSString *logFile = [temp stringByAppendingPathComponent:@"invocations.log"];

        __block BOOL gotMissing = NO;
        __block NSString *missingOut = @"x", *missingReason = nil;
        DPRunCLIReporting(@[@"check"], ^(NSString *output, NSString *reason) {
            missingOut = output;
            missingReason = reason;
            gotMissing = YES;
        });
        pumpUntil(^BOOL { return gotMissing; }, 3);
        expect(gotMissing && !missingOut && missingReason.length > 0, @"missing diapatch reports launch error reason");

        writeStubCLI(cli, [NSString stringWithFormat:
            @"#!/bin/sh\n"
            @"echo \"$*\" >> \"%@\"\n"
            @"if [ \"$1\" = \"noisy\" ]; then\n"
            @"  python3 -c 'import sys; sys.stderr.write(\"e\"*160000); sys.stderr.flush(); sys.stdout.write(\"ok\\n\")'\n"
            @"  exit 0\n"
            @"fi\n"
            @"if [ \"$1\" = \"update\" ]; then\n"
            @"  sleep 0.15\n"
            @"  touch \"%@\"\n"
            @"  echo staged\n"
            @"  exit 0\n"
            @"fi\n"
            @"if [ \"$1\" = \"check\" ]; then\n"
            @"  if [ -f \"%@\" ]; then\n"
            @"    rm -f \"%@\"\n"
            @"    sleep 0.35\n"
            @"    printf '{\"dia\":{\"installed\":\"1.58.0 (100)\",\"latest\":\"1.59.0 (200)\",\"size\":100,\"staged\":null,\"available\":true,\"unpatchable\":null,\"error\":null},\"tweaks\":{\"installed\":\"v1.1.9\",\"latest\":\"v1.1.9\",\"size\":0,\"staged\":null,\"available\":false,\"error\":null}}'\n"
            @"    exit 0\n"
            @"  fi\n"
            @"  if [ -f \"%@\" ]; then\n"
            @"    printf '{\"dia\":{\"installed\":\"1.58.0 (100)\",\"latest\":\"1.59.0 (200)\",\"size\":100,\"staged\":null,\"available\":true,\"unpatchable\":\"bad build 200\",\"error\":null},\"tweaks\":{\"installed\":\"v1.1.9\",\"latest\":\"v1.1.9\",\"size\":0,\"staged\":null,\"available\":false,\"error\":null}}'\n"
            @"    exit 0\n"
            @"  fi\n"
            @"  if [ -f \"%@\" ]; then\n"
            @"    printf '{\"dia\":{\"installed\":\"1.58.0 (100)\",\"latest\":null,\"size\":null,\"staged\":\"1.59.0 (200)\",\"available\":false,\"unpatchable\":null,\"error\":\"offline\"},\"tweaks\":{\"installed\":\"v1.1.9\",\"latest\":\"v1.1.9\",\"size\":0,\"staged\":null,\"available\":false,\"error\":null}}'\n"
            @"    exit 0\n"
            @"  fi\n"
            @"  printf '{\"dia\":{\"installed\":\"1.58.0 (100)\",\"latest\":\"1.60.0 (201)\",\"size\":100,\"staged\":null,\"available\":true,\"unpatchable\":null,\"error\":null},\"tweaks\":{\"installed\":\"v1.1.9\",\"latest\":\"v1.1.9\",\"size\":0,\"staged\":null,\"available\":false,\"error\":null}}'\n"
            @"  exit 0\n"
            @"fi\n"
            @"exit 0\n", logFile, flagFile, gateFile, gateFile, unpatchFile, flagFile]);

        __block BOOL gotNoisy = NO;
        __block NSString *noisyOut = nil;
        DPRunCLIReporting(@[@"noisy"], ^(NSString *output, NSString *reason) {
            noisyOut = output;
            gotNoisy = YES;
        });
        pumpUntil(^BOOL { return gotNoisy; }, 5);
        expect(gotNoisy && [noisyOut isEqualToString:@"ok\n"], @"large stderr does not deadlock DPRunCLIReporting");

        DPUpdates *updates = DPUpdates.shared;
        [NSData.data writeToFile:unpatchFile atomically:YES];
        __block BOOL checked = NO;
        [updates check:^{ checked = YES; }];
        pumpUntil(^BOOL { return checked; }, 5);
        expect([updates failed:DPDia] && [[updates failure:DPDia] isEqualToString:@"bad build 200"], @"unpatchable sets failure");

        [NSFileManager.defaultManager removeItemAtPath:unpatchFile error:nil];
        checked = NO;
        [updates check:^{ checked = YES; }];
        pumpUntil(^BOOL { return checked; }, 5);
        expect(![updates failed:DPDia], @"stale unpatchable error clears on newer patchable build");

        [NSData.data writeToFile:gateFile atomically:YES];
        __block BOOL staleCheckDone = NO, downloadDone = NO, stagedOnDownloadDone = NO;
        [updates check:^{ staleCheckDone = YES; }];
        [updates download:DPDia then:^{
            downloadDone = YES;
            stagedOnDownloadDone = [updates staged:DPDia];
        }];
        pumpUntil(^BOOL { return downloadDone; }, 5);
        expect(staleCheckDone && downloadDone && stagedOnDownloadDone, @"download finishing during in-flight check triggers fresh check seeing staged build");

        DPSoftwareUpdateView *suView = [[DPSoftwareUpdateView alloc] initWithFrame:NSMakeRect(0, 0, 560, 400)];
        expect(hasLabelText(suView, @"Dia 1.59.0 (200)"), @"Software Update shows staged version when offline");
        expect(!hasLabelText(suView, @"<null>"), @"Software Update never shows <null> for staged version");

        [updates pretend:DPTweaks];
        [updates download:DPTweaks then:nil];
        expect([updates downloading:DPTweaks], @"pretend download marks downloading");
        [updates stopPretending];
        expect(![updates downloading:DPTweaks], @"stopPretending clears downloading state");

        NSString *stagedDia = DPSupport(@"staged/Dia.app");
        NSString *stagedReady = DPSupport(@"staged/ready");
        [NSFileManager.defaultManager createDirectoryAtPath:stagedDia withIntermediateDirectories:YES attributes:nil error:nil];
        [@"" writeToFile:logFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        DPHandedOff = NO;
        DPInstallOnQuit();
        usleep(100000);
        NSString *logAfterUnready = [NSString stringWithContentsOfFile:logFile encoding:NSUTF8StringEncoding error:nil];
        expect(![logAfterUnready containsString:@"apply"], @"DPInstallOnQuit skips unready staged Dia.app");

        [NSData.data writeToFile:stagedReady atomically:YES];
        DPInstallOnQuit();
        pumpUntil(^BOOL {
            return [[NSString stringWithContentsOfFile:logFile encoding:NSUTF8StringEncoding error:nil] containsString:@"apply --wait"];
        }, 3);
        NSString *logAfterReady = [NSString stringWithContentsOfFile:logFile encoding:NSUTF8StringEncoding error:nil];
        expect([logAfterReady containsString:@"apply --wait"], @"DPInstallOnQuit launches apply when staged/ready exists");

        [@"" writeToFile:logFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        DPHandOffAndQuit(@[@"uninstall"]);
        expect(DPTerminateCount == 1 && DPHandedOff, @"DPHandOffAndQuit marks handoff and terminates");
        DPHandOffAndQuit(@[@"apply"]);
        expect(DPTerminateCount == 1, @"second DPHandOffAndQuit is deduplicated and does not double-terminate");
        DPInstallOnQuit();
        usleep(150000);
        NSString *logAfterHandoff = [NSString stringWithContentsOfFile:logFile encoding:NSUTF8StringEncoding error:nil];
        expect([logAfterHandoff containsString:@"uninstall --wait"] && ![logAfterHandoff containsString:@"apply --wait"],
               @"DPInstallOnQuit and duplicate handoff do not spawn racing apply after DPHandOffAndQuit uninstall");

        writeStubCLI(cli, @"#!/bin/sh\nprintf '{\"dia\":null,\"tweaks\":{\"installed\":\"v1.1.9\",\"latest\":\"v1.2.0\",\"size\":10,\"staged\":null,\"available\":true,\"releaseNotes\":\"\",\"error\":null}}'\n");
        checked = NO;
        [updates check:^{ checked = YES; }];
        pumpUntil(^BOOL { return checked; }, 5);
        expect(![updates available:DPDia] && ![updates staged:DPDia] && [updates available:DPTweaks],
               @"non-dictionary dia entry in check JSON handled safely without exception");
        DPSoftwareUpdateView *emptyNotesView = [[DPSoftwareUpdateView alloc] initWithFrame:NSMakeRect(0, 0, 560, 400)];
        expect(!hasLabelText(emptyNotesView, @"Release Notes"), @"empty releaseNotes string does not render broken Release Notes link");

        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:DPTestDomain()];
        [NSFileManager.defaultManager removeItemAtPath:temp error:nil];
        (void)DPLaunchedArgs;
    }
    if (!failures) printf("all updates runtime checks passed\n");
    return failures ? 1 : 0;
}
