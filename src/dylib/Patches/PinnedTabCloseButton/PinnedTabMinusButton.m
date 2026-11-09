#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

// Dia gives an open tab under a folded pinned folder a minus button that closes its page and keeps the tab. This gives
// every open pinned tab one. A click is sent as Dia's closeKeepingTab style, which does the same for any pinned tab.
// An option of the close button, which already shows the button on pinned tabs outside a folder.

enum { DPCloseKeepingTab = 1, DPDismiss = 2 };  // TabUI.TabCloseButtonStyle.

static NSImage *DPMinus;
static char DPDiaImageKey;

// The page's attributes, while the tab shows a web page: the controller holds an enum whose other cases set top bits.
static id DPAttributes(NSView *content) {
    void **slot = DPIvar(DPViewModelDelegate(content), "attributesController");
    uintptr_t raw = slot ? (uintptr_t)*slot : 0;
    if (!raw || (raw & 0xF000000000000007)) return nil;
    id attributes = (__bridge id)(void *)raw;
    return DPIsKind(attributes, "_TtC5TabUI33TabWebContentAttributesController") ? attributes : nil;
}

// Dia keeps activeURL while a pinned tab has its page, and clears it when the tab closes.
static BOOL DPIsOpenPinned(NSView *content) {
    id attributes = DPAttributes(content);
    BOOL *pinned = DPIvar(attributes, "isInFavoritesOrPinnedContainer");
    void **activeURL = DPIvar(attributes, "activeURL");
    return pinned && *pinned && activeURL && *activeURL;
}

// The tab controller of an open pinned tab with one page, unless Dia already gives it a minus button.
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
    NSButton *button = DPCloseButton(self);
    if (!button) return;
    id controller = DPMinusOn() ? DPMinusController(self) : nil;
    if (controller && button.image != DPMinus) {
        DPSet(button, &DPDiaImageKey, button.image);
        button.image = DPMinus;
    } else if (!controller && button.image == DPMinus) {
        button.image = DPGet(button, &DPDiaImageKey);
    }
}

static void DPContent_closeButtonClicked(NSView *self, SEL _cmd) {
    id controller = DPMinusOn() ? DPMinusController(self) : nil;
    uint8_t *style = DPIvar(controller, "requestedCloseButtonStyle");
    if (!style) {
        DPCallOriginal(DPContent_closeButtonClicked, self);
        return;
    }
    uint8_t dia = *style;
    *style = DPCloseKeepingTab;  // Dia reads it while handling the click.
    DPCallOriginal(DPContent_closeButtonClicked, self);
    *style = dia;
}

static void DPApplyPinnedTabMinusButton(DPPatch *patch) { DPRelayoutTabContents(); }

static NSString *DPVerifyPinnedTabMinusButton(DPPatch *patch) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) {
        NSButton *button = DPCloseButton(content);
        if (!button || content.needsLayout) continue;
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
    .tint = @"systemPinkColor",
    .requires = @"pinnedTabCloseButton",
    .classes = DPClasses(DPDiaTabView, DPDiaTabContentView),
    .install = DPInstallPinnedTabMinusButton,
    .apply = DPApplyPinnedTabMinusButton,
    .verify = DPVerifyPinnedTabMinusButton,
};
