#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

enum { DPDismiss = 2 };

static NSImage *DPMinus;
static char DPDiaImageKey;
static BOOL DPMinusShown;

static id DPMinusController(NSView *content) {
    NSView *tab = DPEnclosingTab(content);
    if (!tab || !DPIsOpenPinned(content) || [DPSwiftValue(tab, @"contentViews") count] != 1) return nil;
    id controller = DPViewModelDelegate(tab);
    uint8_t *style = DPIvar(controller, "requestedCloseButtonStyle");
    return style && *style != DPDismiss ? controller : nil;
}

static BOOL DPMinusOn(void) { return DPPinnedTabCloseButton.on && DPPinnedTabMinusButton.on; }

static NSButton *DPCloseButton(NSView *content) {
    void **button = DPIvar(content, "$__lazy_storage_$_closeButton");
    return button && *button ? (__bridge NSButton *)*button : nil;
}

static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    BOOL on = DPMinusOn();
    if (!on && !DPMinusShown) return;
    NSButton *button = DPCloseButton(self);
    if (!button || (!on && !DPGet(button, &DPDiaImageKey))) return;
    NSImage *dia = DPDiaValue(button, &DPDiaImageKey, button.image);
    if (!dia) {
        if (!on) DPSet(button, &DPDiaImageKey, nil);
        return;
    }
    BOOL minus = on && DPMinusController(self);
    if (minus) DPOverride(button, &DPDiaImageKey, dia, DPMinus), DPMinusShown = YES;
    else if (DPGet(button, &DPDiaImageKey)) DPSet(button, &DPDiaImageKey, nil);
    NSImage *shown = minus ? DPMinus : dia;
    if (button.image != shown) button.image = shown;
}

// Gate on the shown icon so a stale minus still keeps the tab pinned.
static void DPContent_closeButtonClicked(NSView *self, SEL _cmd) {
    if (!DPMinusOn() || DPCloseButton(self).image != DPMinus
        || !DPClickKeepingTab(self, ^{ DPCallOriginal(DPContent_closeButtonClicked, self); }))
        DPCallOriginal(DPContent_closeButtonClicked, self);
}

static void DPApplyPinnedTabMinusButton(DPPatch *patch) { DPRelayoutTabContents(); }

static NSString *DPVerifyPinnedTabMinusButton(DPPatch *patch) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) {
        id controller = DPViewModelDelegate(content);
        NSButton *button = DPCloseButton(content);
        if (!controller || !button || content.needsLayout) continue;
        if (!DPIvar(controller, "attributesController")) return @"can't tell which tabs have a page open";
        id attributes = DPAttributes(content);
        if (attributes && !(DPIvar(attributes, "activeURL") && DPIvar(attributes, "isInFavoritesOrPinnedContainer")))
            return @"can't tell which tabs have a page open";
        BOOL minus = button.image == DPMinus;
        if (DPMinusOn() && DPMinusController(content) && !minus) return @"open pinned tab has no minus button";
        if (!DPMinusOn() && minus) return @"tab keeps the minus button";
    }
    return nil;
}

static void DPInstallPinnedTabMinusButton(void) {
    DPMinus = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Close"];
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
    DPHook(DPDiaTabContentView, NSSelectorFromString(@"closeButtonClicked"), (IMP)DPContent_closeButtonClicked);
}

DP_PATCH(DPPinnedTabMinusButton) {
    .key = @"pinnedTabMinusButton",
    .order = 86,
    .title = @"Minus Button on Open Pinned Tabs",
    .detail = @"Show a minus button instead on pinned tabs with a page open, in or out of a folder, as in Arc. It closes the page and keeps the tab pinned.",
    .symbol = @"minus.circle.fill",
    .tint = @"systemTealColor",
    .requires = @"pinnedTabCloseButton",
    .classes = DPClasses(DPDiaTabView, DPDiaTabContentView, DPDiaTabPageAttributes),
    .install = DPInstallPinnedTabMinusButton,
    .apply = DPApplyPinnedTabMinusButton,
    .verify = DPVerifyPinnedTabMinusButton,
};
