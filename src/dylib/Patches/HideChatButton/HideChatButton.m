#import "StdPatch/StdPatch.h"

DP_PATCH(DPHideChatButton) {
    .key = @"hideChatButton",
    .order = 95,
    .title = @"Hide Chat Button",
    .detail = @"Hide the Chat button at the top right of the toolbar.",
    .symbol = @"bubble.fill",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .group = @"aiPrompts",
    .classes = DPClasses(DPDiaToolbar),
    .disabledBy = @"hideToolbar",
    .hides = DPIsChatButton,
    .coveredBy = @"turnOffAI",
};
