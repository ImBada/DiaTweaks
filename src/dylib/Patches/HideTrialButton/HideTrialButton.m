#import "StdPatch/Hide.h"

static BOOL DPIsTrialButton(NSView *view) { return DPIsKind(view, DPDiaTrialButton); }

// The pill doesn't clip, so host it wherever Dia puts it rather than trusting the toolbar.
static void DPTrialButton_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPTrialButton_layout, self);
}

static void DPInstallHideTrialButton(void) {
    DPHook(DPDiaTrialButton, @selector(layout), (IMP)DPTrialButton_layout);
}

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
