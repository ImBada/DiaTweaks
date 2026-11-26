#import "StdPatch/StdPatch.h"
#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"
#import "Test/Test.h"
#import "DevTools/DevTools.h"

__attribute__((constructor)) static void DPInit(void) {
    BOOL diapatch = [NSProcessInfo.processInfo.processName isEqualToString:@"diapatch"];
    const char *manifest = getenv("DIAPATCH_MANIFEST");
    if (manifest && diapatch) _exit(DPWriteManifest(@(manifest)) ? 0 : 1);
    // diapatch runs the command once dlopen returns: an initializer holds dyld's lock, which the network stack needs.
    if (getenv("DIAPATCH_LOCAL_BUILD") && diapatch) return;
    if (DPIsChildProcess()) return;
    // Anything else that links the dylib, like a test binary, would otherwise patch itself against the real DiaPatches folder.
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"company.thebrowser.dia"] && !getenv("DIAPATCH_FORCE_INIT")) return;
    DPBeginLaunch();
    if (DPSafeMode == 2) return;
    DPMigrateSettings(DPSettingsDefaults());
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
    unsetenv("DIAPATCH_TEST");  // a relaunched Dia would inherit it and test again
    DPRunTests(path);
}
