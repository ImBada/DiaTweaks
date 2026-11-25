#import "StdPatch/Hide.h"

static BOOL DPIsTrialButton(NSView *view) { return DPIsKind(view, DPDiaTrialButton); }

static void DPInstallHideTrialButton(void) { DPHostHides(DPDiaTrialButton); }

DP_PATCH(DPHideTrialButton) {
    .key = @"hideTrialButton",
    .order = 95,
    .section = @"AI",
    .group = @"aiPrompts",
    .title = @"Hide Trial Button",
    .detail = @"Hide the “Better Days Trial” button at the top right of the toolbar.",
    .symbol = @"creditcard.fill",
    .tint = @"systemPurpleColor",
    .classes = DPClasses(DPDiaToolbar, DPDiaTrialButton),
    .disabledBy = @"hideToolbar",
    .hides = DPIsTrialButton,
    .install = DPInstallHideTrialButton,
    .coveredBy = @"turnOffAI",
};
