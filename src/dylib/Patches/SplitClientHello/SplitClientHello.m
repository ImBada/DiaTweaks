#import "SplitClientHello.h"
#import "Updates/Updates.h"

// Chromium runs its network service in a sandboxed helper that the dylib isn't loaded into, so while this is on the
// service runs inside Dia, where Send.m sees what it sends. Chromium decides that only as Dia starts.

static BOOL gInProcess;

static void DPInstallSplitClientHello(void) {
    DPInstallSplitSend();
    DPSplitting = gInProcess = DPSplitClientHello.on;
    if (gInProcess) DPAddLaunchFlag(@"--enable-features=NetworkServiceInProcess2");
}

static void DPApplySplitClientHello(DPPatch *patch) {
    DPSplitting = patch->on && gInProcess;
    if (patch->on == gInProcess || patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to split ClientHellos" : @"Relaunch Dia to sandbox its network service again";
    alert.informativeText = patch->on ? @"Until then, Dia sends them whole." : @"Dia already sends ClientHellos whole.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPSplitClientHello) {
    .key = @"splitClientHello",
    .order = 120,
    .section = @"Network",
    .title = @"Split TLS ClientHello",
    .detail = @"Send the first message of each secure connection in two pieces, cut at a random point in the site's name. This gets past some networks that block sites by name, but not DNS or address blocks, and a few servers refuse it. While it's on, Dia's network service runs unsandboxed.",
    .symbol = @"network.badge.shield.half.filled network",
    .tint = @"systemCyanColor",
    .install = DPInstallSplitClientHello,
    .apply = DPApplySplitClientHello,
};
