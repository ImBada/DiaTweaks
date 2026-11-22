#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

extern DPPatch DPPasskeys;

static NSString *const kExtensionID = @"ljonmeeapeagnkmjklinbocjbjepecce";

static NSString *const kFiles[] = { @"manifest.json", @"page.js", @"bridge.js", @"worker.js" };

static NSString *const kHostFile = @"com.diapatches.passkeys.json";

static NSString *DPExtensionFolder(void) { return DPAppSupport(@"DiaPatches/passkeys-extension"); }

static NSError *gWriteError;
static NSString *gWritePath;

static BOOL DPWrite(NSData *data, NSString *path) {
    NSError *error;
    if ([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
        && [data writeToFile:path options:NSDataWritingAtomic error:&error])
        return YES;
    gWriteError = error;
    gWritePath = path;
    return NO;
}

static BOOL DPSetUpPasskeys(void) {
    gWriteError = nil;
    gWritePath = nil;
    NSString *folder = DPExtensionFolder();
    for (int i = 0; i < 4; i++) {
        NSString *section = [@"__pk_" stringByAppendingString:kFiles[i].stringByDeletingPathExtension];
        unsigned long size = 0;
        uint8_t *bytes = getsectiondata(&_mh_dylib_header, "__TEXT", section.UTF8String, &size);
        if (!bytes || !DPWrite([NSData dataWithBytes:bytes length:size], [folder stringByAppendingPathComponent:kFiles[i]])) return NO;
    }
    NSError *error = nil;
    NSString *hostFolder = DPHostFolder(YES, &error);
    if (!hostFolder) {
        gWriteError = error;
        gWritePath = [DPHostFolders().lastObject stringByAppendingPathComponent:kHostFile];
        return NO;
    }
    NSDictionary *manifest = @{
        @"name" : @"com.diapatches.passkeys",
        @"description" : @"DiaTweaks passkeys",
        @"path" : DPAppSupport(@"DiaPatches/bin/diapatch"),
        @"type" : @"stdio",
        @"allowed_origins" : @[ [NSString stringWithFormat:@"chrome-extension://%@/", kExtensionID] ],
    };
    if (!DPWrite([NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil],
                 [hostFolder stringByAppendingPathComponent:kHostFile]))
        return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *dir in DPHostFolders()) {
        if ([dir isEqualToString:hostFolder]) continue;
        NSString *stale = [dir stringByAppendingPathComponent:kHostFile];
        if ([fm fileExistsAtPath:stale]) [fm removeItemAtPath:stale error:nil];
    }
    return YES;
}

static NSString *DPPasskeysProblem(DPPatch *patch) {
    NSString *folder = DPExtensionFolder();
    if (gWriteError) return DPWriteProblem(gWritePath ?: folder, gWriteError);
    NSFileManager *fm = NSFileManager.defaultManager;
    for (int i = 0; i < 4; i++) {
        NSString *file = [folder stringByAppendingPathComponent:kFiles[i]];
        if (![fm fileExistsAtPath:file]) return [NSString stringWithFormat:@"%@ is missing.", file];
    }
    NSString *manifest = [DPHostFolder(NO, nil) stringByAppendingPathComponent:kHostFile];
    return DPRelayProblem() ?: DPHostProblem(manifest, @"com.diapatches.passkeys");
}

static BOOL gExtensionLoaded;

static void DPShowHelper(NSNotification *note) {
    if (!DPPasskeys.on) return;
    NSRunningApplication *helper = [NSRunningApplication runningApplicationWithProcessIdentifier:[note.object intValue]];
    void (^show)(void) = ^{ [helper activateFromApplication:NSRunningApplication.currentApplication options:NSApplicationActivateAllWindows]; };
    if (![note.name hasSuffix:@"signIn"]) return show();
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Sign in to Dia once for passkeys";
    alert.informativeText = @"Passkeys open in a second copy of Dia, which needs you to sign in with your Dia email once. Your passkey carries on after.";
    NSUInteger browser = [NSApp.orderedWindows indexOfObjectPassingTest:^BOOL(NSWindow *window, NSUInteger i, BOOL *stop) { return window.visible && window.canBecomeMainWindow; }];
    if (browser == NSNotFound) return (void)([alert runModal], show());
    [alert beginSheetModalForWindow:NSApp.orderedWindows[browser] completionHandler:^(NSModalResponse _) { show(); }];
}

static void DPInstallPasskeys(void) {
    NSString *folder = DPExtensionFolder();
    if (!DPPasskeys.on) {
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:folder error:nil];
        for (NSString *dir in DPHostFolders()) {
            NSString *path = [dir stringByAppendingPathComponent:kHostFile];
            if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
        }
        DPDropExtension(folder);
        return;
    }
    if (!DPSetUpPasskeys()) return;
    DPLoadExtension(folder);
    gExtensionLoaded = YES;
    for (NSString *name in @[ @"com.diapatches.passkeys.show", @"com.diapatches.passkeys.signIn" ])
        [NSDistributedNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPShowHelper(note); }];
}

static void DPApplyPasskeys(DPPatch *patch) {
    if (patch->on) DPSetUpPasskeys();
    if (patch->on == gExtensionLoaded || patch->on != DPSavedOn(patch) || (patch->on && DPPasskeysProblem(patch))) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to allow iCloud passkeys" : @"Relaunch Dia to stop using iCloud passkeys";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPPasskeys) {
    .key = @"passkeys",
    .order = 100,
    .title = @"Allow iCloud Passkeys",
    .detail = @"Sign in to sites with passkeys saved in Apple Passwords. A patched Dia can’t reach them, so the original Dia that DiaTweaks keeps opens behind the Touch ID prompt, then quits. A password manager with passkeys of its own, such as Proton Pass, keeps its prompt. Experimental.",
    .symbol = @"person.badge.key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .relaunch = YES,
    .install = DPInstallPasskeys,
    .apply = DPApplyPasskeys,
    .ready = DPPasskeysProblem,
};
