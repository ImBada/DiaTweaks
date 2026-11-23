#import "Patches/DestinationToggleEngineName/DestinationToggleEngineName.h"

extern DPPatch DPDestinationToggleEngineName;

static NSString *const DPGoogle = @"Google";
static NSString *const DPChat = @"Chat";

@protocol DPEngineNameChain
- (id)context;
- (id)preferences;
- (id)getDefaultSearchEngine;
- (NSString *)name;
@end

static NSMapTable<NSWindow *, id> *DPBrowsers;
static char DPTextKey, DPLabelKey, DPTipKey;
// Set while Dia's own "Google" is still swapped out somewhere, so turning the tweak off knows to sweep.
static BOOL DPApplied;

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    if (window) [DPBrowsers setObject:self forKey:window];
}

NSString *DPEngineNameForWindow(NSWindow *window) {
    id browser = nil;
    for (NSWindow *w = window; w && !browser; w = w.parentWindow) browser = [DPBrowsers objectForKey:w];
    id context = [(id<DPEngineNameChain>)browser context];
    id preferences = [(id<DPEngineNameChain>)context preferences];
    id engine = [(id<DPEngineNameChain>)preferences getDefaultSearchEngine];
    NSString *name = [(id<DPEngineNameChain>)engine name];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

NSString *DPEngineDisplayName(NSString *name) {
    NSString *trimmed = [name isKindOfClass:NSString.class] ? [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    return trimmed.length ? trimmed : DPGoogle;
}

static NSArray<NSView *> *DPAllViews(NSView *root) {
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    NSMutableArray<NSView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        NSView *view = stack.lastObject;
        [stack removeLastObject];
        [views addObject:view];
        [stack addObjectsFromArray:view.subviews];
    }
    return views;
}

static NSString *DPTextOf(NSView *view) {
    if ([view isKindOfClass:NSTextField.class]) return ((NSTextField *)view).stringValue;
    if ([view isKindOfClass:NSTextView.class]) return ((NSTextView *)view).string;
    return nil;
}

static void DPSetText(NSView *view, NSString *text) {
    if ([view isKindOfClass:NSTextField.class]) ((NSTextField *)view).stringValue = text;
    else if ([view isKindOfClass:NSTextView.class]) ((NSTextView *)view).string = text;
}

static BOOL DPHasText(NSArray<NSView *> *views, NSString *text) {
    for (NSView *view in views) if ([DPTextOf(view) isEqualToString:text]) return YES;
    return NO;
}

static BOOL DPInside(NSView *view, Class cls) {
    for (NSView *up = view; up; up = up.superview) if (cls && [up isKindOfClass:cls]) return YES;
    return NO;
}

static BOOL DPInsideAddressField(NSView *view) {
    Class field = objc_getClass(DPDiaAddressField), toggle = objc_getClass(DPDiaToggleControl);
    for (NSView *up = view; up; up = up.superview)
        if ((field && [up isKindOfClass:field]) || (toggle && [up isKindOfClass:toggle])) return YES;
    return NO;
}

// True while any view still holds Dia's word in an override, so a restore finds the dropdown after its "Google" row was renamed.
static BOOL DPAnyOverride(NSArray<NSView *> *views) {
    for (NSView *view in views) if (DPGet(view, &DPTextKey)) return YES;
    return NO;
}

// A view we already renamed keeps Dia's word in the override, so a new engine name replaces the old one.
static BOOL DPRelabelText(NSView *view, NSString *name) {
    NSString *text = DPTextOf(view);
    if (!text.length) return NO;
    NSArray *override = DPGet(view, &DPTextKey);
    BOOL ours = override && [override[1] isEqual:text];
    NSString *dia = ours ? override[0] : text;
    if (name && ![name isEqualToString:DPGoogle]) {
        if ([text isEqualToString:name] || ![dia isEqualToString:DPGoogle]) return NO;
        DPOverride(view, &DPTextKey, dia, name);
        DPSetText(view, name);
        return YES;
    }
    if (!ours || [dia isEqualToString:text]) return NO;
    DPSetText(view, dia);
    return YES;
}

static NSString *DPReplaced(NSString *text, NSString *name) {
    NSRange range = [text rangeOfString:DPGoogle];
    return range.location == NSNotFound ? text : [text stringByReplacingCharactersInRange:range withString:name];
}

// Dia's onboarding tooltip is one sentence ("Click to toggle between Chat and Google") with no separate rows,
// so match the sentence and keep Dia's original in the override for a restore.
static NSString *const DPTooltipSentence = @"Click to toggle between Chat and ";

static BOOL DPRelabelSentence(NSArray<NSView *> *views, NSString *name) {
    BOOL changed = NO;
    for (NSView *view in views) {
        NSString *text = DPTextOf(view);
        if (!text.length) continue;
        NSArray *override = DPGet(view, &DPTextKey);
        BOOL ours = override && [override[1] isEqual:text];
        NSString *dia = ours ? override[0] : text;
        if (![dia hasPrefix:DPTooltipSentence] || [dia rangeOfString:DPGoogle].location == NSNotFound) continue;
        if (name && ![name isEqualToString:DPGoogle]) {
            NSString *wanted = DPReplaced(dia, name);
            if ([text isEqualToString:wanted]) continue;
            DPOverride(view, &DPTextKey, dia, wanted);
            DPSetText(view, wanted);
            changed = YES;
        } else {
            if (!ours || [dia isEqualToString:text]) continue;
            DPSetText(view, dia);
            changed = YES;
        }
    }
    return changed;
}

static BOOL DPRelabelChrome(NSView *view, NSString *name) {
    BOOL changed = NO;
    NSString *label = view.accessibilityLabel, *tip = view.toolTip;
    NSArray *labelOverride = DPGet(view, &DPLabelKey), *tipOverride = DPGet(view, &DPTipKey);
    BOOL labelOurs = labelOverride && [labelOverride[1] isEqual:label], tipOurs = tipOverride && [tipOverride[1] isEqual:tip];
    NSString *diaLabel = labelOurs ? labelOverride[0] : label, *diaTip = tipOurs ? tipOverride[0] : tip;
    if (name && ![name isEqualToString:DPGoogle]) {
        NSString *wantedLabel = DPReplaced(diaLabel, name), *wantedTip = DPReplaced(diaTip, name);
        if (label.length && ![label isEqualToString:wantedLabel] && [diaLabel rangeOfString:DPGoogle].location != NSNotFound) {
            DPOverride(view, &DPLabelKey, diaLabel, wantedLabel);
            view.accessibilityLabel = wantedLabel;
            changed = YES;
        }
        if (tip.length && ![tip isEqualToString:wantedTip] && [diaTip rangeOfString:DPGoogle].location != NSNotFound) {
            DPOverride(view, &DPTipKey, diaTip, wantedTip);
            view.toolTip = wantedTip;
            changed = YES;
        }
        return changed;
    }
    if (labelOurs && ![diaLabel isEqual:label]) view.accessibilityLabel = diaLabel, changed = YES;
    if (tipOurs && ![diaTip isEqual:tip]) view.toolTip = diaTip, changed = YES;
    return changed;
}

static void DPInvalidate(NSView *view) {
    for (NSView *up = view; up; up = up.superview) [up invalidateIntrinsicContentSize];
}

BOOL DPRelabelEngineText(NSView *root, NSString *name) {
    if (!root) return NO;
    NSArray<NSView *> *views = DPAllViews(root);
    Class toggle = objc_getClass(DPDiaToggleControl);
    // The Chat/Search dropdown is the only view that lists both halves; the address field never is, and its page title can read "Google" too.
    BOOL menu = !DPIsKind(root, DPDiaAddressField) && DPHasText(views, DPChat) && (DPHasText(views, DPGoogle) || DPAnyOverride(views));
    NSMutableArray<NSView *> *changed = [NSMutableArray new];
    for (NSView *view in views) {
        if (!menu && !DPInside(view, toggle)) continue;
        BOOL text = DPRelabelText(view, name);
        BOOL chrome = (menu || (toggle && [view isKindOfClass:toggle])) && DPRelabelChrome(view, name);
        if (text || chrome) [changed addObject:view];
    }
    for (NSView *view in changed) DPInvalidate(view);
    BOOL sentence = DPRelabelSentence(views, name);
    if (changed.count || sentence) DPApplied = YES;
    return changed.count > 0 || sentence;
}

BOOL DPRelabelPopover(NSPopover *popover, NSString *name) {
    NSView *content = popover.contentViewController.view;
    return content ? DPRelabelEngineText(content, name) : NO;
}

static BOOL DPRelabelMenuItem(NSMenuItem *item, NSString *name) {
    NSString *title = item.title;
    if (!title.length) return NO;
    NSArray *override = DPGet(item, &DPTextKey);
    BOOL ours = override && [override[1] isEqual:title];
    NSString *dia = ours ? override[0] : title;
    if (name && ![name isEqualToString:DPGoogle]) {
        if ([title isEqualToString:name] || ![dia isEqualToString:DPGoogle]) return NO;
        DPOverride(item, &DPTextKey, dia, name);
        item.title = name;
        return YES;
    }
    if (!ours || [dia isEqualToString:title]) return NO;
    item.title = dia;
    return YES;
}

BOOL DPRelabelMenu(NSMenu *menu, NSString *name) {
    if (!menu) return NO;
    BOOL changed = NO;
    for (NSMenuItem *item in menu.itemArray) {
        changed |= DPRelabelMenuItem(item, name);
        if (item.submenu) changed |= DPRelabelMenu(item.submenu, name);
    }
    if (changed) DPApplied = YES;
    return changed;
}

static BOOL DPMenuHasTitle(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title]) return YES;
        if (item.submenu && DPMenuHasTitle(item.submenu, title)) return YES;
    }
    return NO;
}

static BOOL DPMenuAnyOverride(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if (DPGet(item, &DPTextKey)) return YES;
        if (item.submenu && DPMenuAnyOverride(item.submenu)) return YES;
    }
    return NO;
}

// Dia may present the dropdown as an NSMenu from a shared helper, so relabel it before it starts tracking.
BOOL DPApplyMenu(NSMenu *menu, NSView *view) {
    if (!menu || !view) return NO;
    if (!DPDestinationToggleEngineName.on && !DPApplied) return NO;
    if (!DPInsideAddressField(view)) return NO;
    if (!DPMenuHasTitle(menu, DPChat) || !(DPMenuHasTitle(menu, DPGoogle) || DPMenuAnyOverride(menu))) return NO;
    NSString *name = DPDestinationToggleEngineName.on ? DPEngineDisplayName(DPEngineNameForWindow(view.window)) : nil;
    return DPRelabelMenu(menu, name);
}

BOOL DPApplyEngineNameToView(NSView *root, NSWindow *fallbackWindow) {
    if (!root) return NO;
    NSString *name = DPDestinationToggleEngineName.on ? DPEngineDisplayName(DPEngineNameForWindow(root.window ?: fallbackWindow)) : nil;
    if (!name && !DPApplied) return NO;
    return DPRelabelEngineText(root, name);
}

static BOOL DPApply(NSView *root) {
    return DPApplyEngineNameToView(root, nil);
}

// Sweeps every window, so it must not forget DPApplied until the last one is done: Dia's Settings window
// comes first and has no toggle, and clearing it there would leave every browser window still saying "Google".
void DPApplyEngineNameToWindows(void) {
    for (NSWindow *window in NSApp.windows) DPApply(window.contentView);
    if (!DPDestinationToggleEngineName.on) DPApplied = NO;
}

static void DPBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBar_layout, self);
    DPApply(self);
}

static void DPToggle_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPToggle_updateLayer, self);
    DPApply(self);
}

static void DPNSPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *view, NSRectEdge edge) {
    DPCallOriginal(DPNSPopover_show, self, rect, view, edge);
    if (!DPDestinationToggleEngineName.on && !DPApplied) return;
    NSView *content = self.contentViewController.view;
    if (!content) return;
    DPApplyEngineNameToView(content, view.window);
    // The rows can be built on the popover's first layout, after it is already on screen.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isShown) DPApplyEngineNameToView(content, view.window);
    });
}

static void DPDynamicPopover_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPDynamicPopover_layout, self);
    DPApply(self);
}

// Both menu entry points block in the menu's tracking run loop, so titles must be right beforehand.
static BOOL DPNSMenu_popUp(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    DPApplyMenu(self, view);
    return DPCallOriginal(DPNSMenu_popUp, self, item, location, view);
}

static void DPNSMenu_popUpContext(NSMenu *self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view) {
    DPApplyMenu(menu, view);
    DPCallOriginal(DPNSMenu_popUpContext, self, menu, event, view);
}

static void DPApplyDestinationToggleEngineName(DPPatch *patch) {
    DPApplyEngineNameToWindows();
}

static NSString *DPVerifyDestinationToggleEngineName(DPPatch *patch) {
    for (NSView *toggle in DPFindViews(DPDiaToggleControl)) {
        if (toggle.hiddenOrHasHiddenAncestor) continue;
        NSString *name = DPEngineDisplayName(DPEngineNameForWindow(toggle.window));
        if (![name isEqualToString:DPGoogle] && DPHasText(DPAllViews(toggle), DPGoogle)) return @"the Chat toggle still says Google";
    }
    return nil;
}

static void DPInstallDestinationToggleEngineName(void) {
    DPBrowsers = [NSMapTable weakToWeakObjectsMapTable];
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    DPHook(DPDiaAddressField, @selector(layout), (IMP)DPBar_layout);
    DPHook(DPDiaToggleControl, @selector(updateLayer), (IMP)DPToggle_updateLayer);
    DPHook("NSPopover", @selector(showRelativeToRect:ofView:preferredEdge:), (IMP)DPNSPopover_show);
    DPHook(DPDiaPopover, @selector(layout), (IMP)DPDynamicPopover_layout);
    DPHook("NSMenu", @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPNSMenu_popUp);
    DPHookClass(object_getClass(NSMenu.class), @selector(popUpContextMenu:withEvent:forView:), (IMP)DPNSMenu_popUpContext);
}

DP_PATCH(DPDestinationToggleEngineName) {
    .key = @"destinationToggleEngineName",
    .order = 49,
    .title = @"Search Engine Name in Chat Toggle",
    .detail = @"Name your search engine, not “Google”, in the address field’s Chat toggle and its menu, so Kagi, DuckDuckGo and the rest read right.",
    .symbol = @"magnifyingglass.circle.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .disabledBy = @"hideToolbar",
    .classes = DPClasses(DPDiaBrowser, DPDiaAddressField, DPDiaToggleControl),
    .install = DPInstallDestinationToggleEngineName,
    .apply = DPApplyDestinationToggleEngineName,
    .verify = DPVerifyDestinationToggleEngineName,
};
