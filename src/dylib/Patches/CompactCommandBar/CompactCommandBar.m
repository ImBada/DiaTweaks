#import "CompactCommandBar.h"

static NSMapTable<NSView *, NSMapTable *> *DPParts;

// Every layout and keystroke asks for the same few parts, so remember where each was rather than search the bar again.
NSView *DPCommandBarPart(NSView *commandBar, const char *className) {
    if (!commandBar) return nil;
    if (!DPParts) DPParts = [NSMapTable weakToStrongObjectsMapTable];
    NSMapTable *parts = [DPParts objectForKey:commandBar];
    NSView *part = [parts objectForKey:@((uintptr_t)className)];
    if (part && [part isDescendantOf:commandBar]) return part;
    part = DPFindView(commandBar, ^BOOL(NSView *view) { return DPIsKind(view, className); });
    if (!part) return nil;
    if (!parts) [DPParts setObject:parts = [NSMapTable strongToWeakObjectsMapTable] forKey:commandBar];
    [parts setObject:part forKey:@((uintptr_t)className)];
    return part;
}

BOOL DPChatLocked(NSView *view) {
    return DPFindView(view, ^BOOL(NSView *v) { return [v.accessibilityLabel hasSuffix:@"only available when you have chat usage"]; }) != nil;
}

// Dia labels the buttons a moment after the bar shows, so until then the last label decides.
static NSString *const DPChatLockedKey = @"commandBarChatLocked";

void DPRememberChatLocked(BOOL locked) {
    if ([DPSettingsDefaults() boolForKey:DPChatLockedKey] != locked) [DPSettingsDefaults() setBool:locked forKey:DPChatLockedKey];
}

static BOOL DPCompacts(NSView *toolbar) {
    return DPCompactWithChat.on || DPChatLocked(toolbar);
}

static BOOL DPOnCommandBarSurface(NSView *view) {
    for (; view; view = view.superview)
        if ((DPIsKind(view, DPDiaPopover) && !DPIsFloatingChat(view)) || DPIsKind(view, DPDiaNewTabPage) || DPIsKind(view, "DPCommandBarOverlay")) return YES;
    return NO;
}

NSView *DPCompactToolbar(NSView *commandBar) {
    if (!DPCompactCommandBar.on) return nil;
    NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar);
    BOOL compacts = toolbar && (DPCompactWithChat.on || [DPSettingsDefaults() boolForKey:DPChatLockedKey] || DPChatLocked(toolbar));
    return compacts && DPOnCommandBarSurface(commandBar) ? toolbar : nil;
}

NSView *DPGoButton(NSView *toolbar) {
    NSStackView *stack = toolbar.subviews.firstObject;
    return [stack isKindOfClass:NSStackView.class] ? stack.views.lastObject : nil;
}

static char DPTrimKey;

CGFloat DPTrim(NSView *container) {
    return [DPGet(container, &DPTrimKey) doubleValue];
}

void DPSetTrim(NSView *container, CGFloat trim) {
    DPSet(container, &DPTrimKey, trim > 0 ? @(trim) : nil);
}

void DPApplyCompactCommandBar(DPPatch *patch) {
    Class barCls = objc_getClass(DPDiaCommandBar);
    if (!barCls) return;
    for (NSWindow *window in NSApp.windows)
        DPFindView(window.contentView.superview ?: window.contentView, ^BOOL(NSView *view) {
            if ([view isKindOfClass:barCls]) {
                view.needsLayout = YES;
                DPCommandBarPart(view, DPDiaCommandBarInput).needsLayout = YES;
            }
            return NO;
        });
}

static NSString *DPVerifyCompactCommandBar(DPPatch *patch) {
    for (NSView *commandBar in DPFindViews(DPDiaCommandBar)) {
        NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar), *go = DPGoButton(toolbar);
        NSView *input = DPCommandBarPart(commandBar, DPDiaCommandBarInput);
        if (!go || !input || !DPCompacts(toolbar) || !DPOnCommandBarSurface(commandBar)) continue;
        NSRect goFrame = [go convertRect:go.bounds toView:input.superview];
        BOOL beside = NSMinY(goFrame) < NSMaxY(input.frame) && NSMaxY(goFrame) > NSMinY(input.frame);
        if (beside != patch->on) return patch->on ? @"Go is still under the input" : @"Go is still beside the input";
        NSView *panel = commandBar.superview.superview;
        if (DPIsKind(panel, DPDiaAssistantPanel) && DPIsKind(panel.superview.superview, DPDiaNewTabPage)
            && (NSHeight(panel.frame) < NSHeight(commandBar.frame) - 0.5) != patch->on)
            return patch->on ? @"new tab page keeps the empty row" : @"new tab page is still trimmed";
    }
    return nil;
}

DP_PATCH(DPCompactCommandBar) {
    .key = @"compactCommandBar",
    .order = 90,
    .section = @"Command Bar",
    .title = @"Compact Command Bar",
    .detail = @"Without chat usage, hide Add tabs or files and dictation so the command bar fits on one line.",
    .symbol = @"rectangle.compress.vertical",
    .tint = @"systemOrangeColor",
    .classes = DPClasses(DPDiaPopover, DPDiaAssistantPanel, DPDiaNewTabPage, DPDiaCommandBar, DPDiaCommandBarInput, DPDiaCommandBarText, DPDiaCommandBarSuggestions, DPDiaCommandBarToolbar, DPDiaCommandBarButton),
    .install = DPInstallCommandBarLayout,
    .apply = DPApplyCompactCommandBar,
    .verify = DPVerifyCompactCommandBar,
};
