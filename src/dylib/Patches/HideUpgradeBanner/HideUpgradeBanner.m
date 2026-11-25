#import "StdPatch/Hide.h"

static BOOL DPIsUpgradeBanner(NSView *view) { return DPIsKind(view, DPDiaChatUsage); }

static void DPInstallHideUpgradeBanner(void) { DPHostHides(DPDiaChatUsage); }

DP_PATCH(DPHideUpgradeBanner) {
    .key = @"hideUpgradeBanner",
    .order = 95,
    .section = @"AI",
    .group = @"aiPrompts",
    .title = @"Hide Upgrade Banner",
    .detail = @"Hide the “Looking for chat?” upgrade banner under the command bar.",
    .symbol = @"crown.fill",
    .tint = @"systemPurpleColor",
    .classes = DPClasses(DPDiaChatUsage),
    .hides = DPIsUpgradeBanner,
    .install = DPInstallHideUpgradeBanner,
    .coveredBy = @"turnOffAI",
};
