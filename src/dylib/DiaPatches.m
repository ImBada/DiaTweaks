#import "StdPatch/StdPatch.h"
#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"
#import "Test/Test.h"
#import "DevTools/DevTools.h"

__attribute__((constructor)) static void DPInit(void) {
    // Only honor DIAPATCH_MANIFEST inside diapatch so a stray env var won't exit Dia.
    const char *manifest = getenv("DIAPATCH_MANIFEST");
    if (manifest && [NSProcessInfo.processInfo.processName isEqualToString:@"diapatch"]) _exit(DPWriteManifest(@(manifest)) ? 0 : 1);
    const char *local = getenv("DIAPATCH_LOCAL_BUILD");
    if (local && [NSProcessInfo.processInfo.processName isEqualToString:@"diapatch"]) {
        int status = DPLocalBuildMain(NSProcessInfo.processInfo.arguments) ? 0 : 1;
        fflush(NULL);  // _exit skips stdio, and the report is the whole point of the command.
        _exit(status);
    }
    if (DPIsChildProcess()) return;
    DPBeginLaunch();
    if (DPSafeMode == 2) return;
    DPLoadPatches();
    DPWatchSavedSettings();
    if (!DPSafeMode && !DPPaused) DPInstallPatches();
    else if (DPPaused && !DPSafeMode) DPDropStaleLaunchFlags();
    DPInstallSettings();
    DPInstallUpdates();
    DPInstallDevTools();

    const char *report = getenv("DIAPATCH_TEST");
    if (!report) return;
    NSString *path = @(report);
    unsetenv("DIAPATCH_TEST");  // A relaunched Dia would inherit it and test again.
    DPRunTests(path);
}
