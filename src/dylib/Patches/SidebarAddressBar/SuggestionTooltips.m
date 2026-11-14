#import "Editor.h"

static BOOL DPTooltipIsCovered(void) {
    return DPSidebarSuggestionsContainScreenPoint(NSEvent.mouseLocation);
}
static void DPSuggestionTooltip_orderFront(NSWindow *self, SEL _cmd, id sender) {
    if (!DPTooltipIsCovered()) DPCallOriginal(DPSuggestionTooltip_orderFront, self, sender);
}
static void DPSuggestionTooltip_orderRegardless(NSWindow *self, SEL _cmd) {
    if (!DPTooltipIsCovered()) DPCallOriginal(DPSuggestionTooltip_orderRegardless, self);
}
static void DPSuggestionTooltip_orderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger other) {
    if (place == NSWindowOut || !DPTooltipIsCovered())
        DPCallOriginal(DPSuggestionTooltip_orderWindow, self, place, other);
}

void DPSidebarInstallSuggestionTooltips(void) {
    // Dia uses custom tooltip windows rather than NSView.toolTip for its tabs.
    // These hooks affect only those windows while the pointer covers our list.
    const char *names[] = {
        "_TtC10DiaTooltipP33_7D1C6CBFE46FE0F2FBDE9A178E361D3113TooltipWindow",
        "_TtC10ArcTooltipP33_AD61E6E7B04DE22D34282F3C2DCC179E13TooltipWindow",
        "_TtC7Tooltip13TooltipWindow", NULL};
    for (NSUInteger i = 0; names[i]; i++) {
        const char *name = names[i];
        Class cls = objc_getClass(name);
        if (!cls) continue;
        DPHookClass(cls, @selector(orderFront:), (IMP)DPSuggestionTooltip_orderFront);
        DPHookClass(cls, @selector(orderFrontRegardless), (IMP)DPSuggestionTooltip_orderRegardless);
        DPHookClass(cls, @selector(orderWindow:relativeTo:), (IMP)DPSuggestionTooltip_orderWindow);
        for (NSWindow *window in NSApp.windows)
            if ([window isKindOfClass:cls] && window.isVisible) [window orderOut:nil];
    }
}
