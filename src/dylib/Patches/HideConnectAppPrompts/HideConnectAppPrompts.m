#import "HideConnectAppPrompts.h"
#import "Patches/TurnOffAI/TurnOffAI.h"
#import <objc/message.h>

static Class DPDialogPanelClass, DPDialogButtonClass, DPDialogPanelVCClass, DPDialogPanelWCClass;
static char DPDismissedKey, DPHandledKey, DPDeclineButtonKey, DPHiddenAtLoadKey;
static BOOL DPHidAtLoad;

static BOOL DPSuppressConnectPrompts(void) {
    return DPHideConnectAppPrompts.on || DPTurnOffAI.on;
}

static NSString *DPTrimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL DPIsConnectTitle(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return NO;
    NSString *text = DPTrimmed(raw);
    NSUInteger prefix = [text hasPrefix:@"Connect "] ? 8 : [text hasPrefix:@"Reconnect "] ? 10 : 0;
    if (!prefix || ![text hasSuffix:@" to Dia?"] || text.length <= prefix + 8) return NO;
    return DPTrimmed([text substringWithRange:NSMakeRange(prefix, text.length - prefix - 8)]).length > 0;
}

static BOOL DPIsDeclineTitle(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return NO;
    NSString *lower = [DPTrimmed(raw) stringByReplacingOccurrencesOfString:@"\u2019" withString:@"'"].lowercaseString;
    return [lower hasPrefix:@"don't connect"] || [lower isEqualToString:@"not now"];
}

static BOOL DPIsConnectAppPrompt(NSView *panel) {
    if (!panel || !DPDialogPanelClass || ![panel isKindOfClass:DPDialogPanelClass]) return NO;
    return DPFindView(panel, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && !view.hidden && DPIsConnectTitle(((NSTextField *)view).stringValue);
    }) != nil;
}

// The Ask-on-Page and New Tab single-app upsells are bars, not dialogs: "Bring the full context from <App> into Dia".
BOOL DPIsSingleAppUpsellBar(NSView *view) {
    if (!DPIsKind(view, DPDiaAppsUpsellBar)) return NO;
    return DPFindView(view, ^BOOL(NSView *sub) {
        if (![sub isKindOfClass:NSTextField.class] || sub.hidden) return NO;
        NSString *text = ((NSTextField *)sub).stringValue;
        return [text hasPrefix:@"Bring the full context from "] && [text hasSuffix:@" into Dia"];
    }) != nil;
}

static NSButton *DPDeclineButtonIn(NSView *panel) {
    if (!panel) return nil;
    return (NSButton *)DPFindView(panel, ^BOOL(NSView *view) {
        if (![view isKindOfClass:NSButton.class] || (DPDialogButtonClass && ![view isKindOfClass:DPDialogButtonClass])) return NO;
        NSButton *button = (NSButton *)view;
        return button.target == panel && button.action == @selector(handleButton:) && DPIsDeclineTitle(button.title);
    });
}

static NSView *DPConnectPromptIn(NSView *root, NSButton **declineOut) {
    __block NSButton *matchedDecline = nil;
    NSView *panel = DPFindView(root, ^BOOL(NSView *view) {
        matchedDecline = DPIsConnectAppPrompt(view) ? DPDeclineButtonIn(view) : nil;
        return matchedDecline != nil;
    });
    if (panel && declineOut) *declineOut = matchedDecline;
    return panel;
}

static void DPRestoreHiddenAtLoadIn(NSView *root) {
    if (!root || !DPHidAtLoad) return;
    DPFindView(root, ^BOOL(NSView *view) {
        NSView *host = DPGet(view, &DPHiddenAtLoadKey);
        if (!host) return NO;
        DPSet(view, &DPHiddenAtLoadKey, nil);
        if (![DPGet(view, &DPDismissedKey) boolValue]) {
            host.hidden = NO;
            view.hidden = NO;
        }
        return NO;
    });
}

static void DPHidePromptWindow(NSWindow *window, NSView *panel) {
    window.animationBehavior = NSWindowAnimationBehaviorNone;
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    panel.hidden = YES;
}

static void DPHideOverlayHost(NSView *panel) {
    for (NSView *up = DPDialogPanelVCClass ? panel.superview : nil; up; up = up.superview)
        if ([up.nextResponder isKindOfClass:DPDialogPanelVCClass]) {
            up.hidden = YES;
            break;
        }
    panel.hidden = YES;
}

// Route through Dia's own decline button so Swift continuations and cooldown state clean up without connecting.
static void DPScheduleDecline(NSView *panel, NSButton *decline) {
    if (!panel || !decline || [DPGet(panel, &DPDismissedKey) boolValue] || [DPGet(panel, &DPHandledKey) boolValue]) return;
    DPSet(panel, &DPDismissedKey, @YES);
    DPSet(panel, &DPDeclineButtonKey, decline);
    __weak NSView *weakPanel = panel;
    __weak NSButton *weakDecline = decline;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *p = weakPanel;
        NSButton *b = weakDecline;
        if (!p || !b || [DPGet(p, &DPHandledKey) boolValue] || (!p.window && !p.superview)) return;
        if (b.target != p || b.action != @selector(handleButton:) || ![p respondsToSelector:@selector(handleButton:)]) return;
        ((void (*)(id, SEL, id))objc_msgSend)(p, @selector(handleButton:), b);
    });
}

// A hotkey (Return on a hidden sheet) must not accept a suppressed prompt, and Dia must hear the decline once.
static void DPDialogPanel_handleButton(NSView *self, SEL _cmd, id sender) {
    BOOL suppressed = [DPGet(self, &DPDismissedKey) boolValue];
    if (suppressed) {
        if ([DPGet(self, &DPHandledKey) boolValue]) return;
        id expected = DPGet(self, &DPDeclineButtonKey);
        if (expected && sender != expected) return;
        DPSet(self, &DPHandledKey, @YES);
        DPSet(self, &DPDeclineButtonKey, nil);
        DPCallOriginal(DPDialogPanel_handleButton, self, sender);
        return;
    }
    if (DPSuppressConnectPrompts() && DPIsConnectAppPrompt(self)) DPSet(self, &DPHandledKey, @YES);
    DPCallOriginal(DPDialogPanel_handleButton, self, sender);
}

static void DPWindow_beginSheet(NSWindow *self, SEL _cmd, NSWindow *sheet, void (^handler)(NSModalResponse)) {
    NSButton *decline = nil;
    NSView *panel = nil;
    if (sheet) {
        if (DPSuppressConnectPrompts()) panel = DPConnectPromptIn(sheet.contentView, &decline);
        else DPRestoreHiddenAtLoadIn(sheet.contentView);
    }
    if (panel) DPHidePromptWindow(sheet, panel);
    DPCallOriginal(DPWindow_beginSheet, self, sheet, handler);
    if (panel) DPScheduleDecline(panel, decline);
}

static BOOL DPSuppressPanelWindow(NSWindow *window) {
    if (!DPSuppressConnectPrompts()) {
        DPRestoreHiddenAtLoadIn(window.contentView);
        return NO;
    }
    if (!DPDialogPanelWCClass) return NO;
    if (![window.windowController isKindOfClass:DPDialogPanelWCClass]) return NO;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(window.contentView, &decline);
    if (!panel) return NO;
    DPHidePromptWindow(window, panel);
    DPScheduleDecline(panel, decline);
    return YES;
}

static void DPWindow_makeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) {
    if (DPSuppressPanelWindow(self)) return;
    DPCallOriginal(DPWindow_makeKeyAndOrderFront, self, sender);
}

static void DPWindow_orderFront(NSWindow *self, SEL _cmd, id sender) {
    if (DPSuppressPanelWindow(self)) return;
    DPCallOriginal(DPWindow_orderFront, self, sender);
}

static void DPDialogPanelVC_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPDialogPanelVC_viewDidLoad, self);
    if (!DPSuppressConnectPrompts()) return;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(self.view, &decline);
    if (!panel) return;
    DPHidAtLoad = YES;
    DPSet(panel, &DPHiddenAtLoadKey, self.view);
    self.view.hidden = YES;
    panel.hidden = YES;
}

static void DPDialogPanel_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPDialogPanel_viewDidMoveToWindow, self);
    if (!self.window) return;
    if (!DPSuppressConnectPrompts()) {
        DPRestoreHiddenAtLoadIn(self);
        return;
    }
    if (DPDialogPanelWCClass && [self.window.windowController isKindOfClass:DPDialogPanelWCClass]) return;
    if (!DPIsConnectAppPrompt(self)) return;
    NSButton *decline = DPDeclineButtonIn(self);
    if (!decline) return;
    DPHideOverlayHost(self);
    DPScheduleDecline(self, decline);
}

static void DPDismissInWindow(NSWindow *window) {
    if (!window.contentView) return;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(window.contentView, &decline);
    if (!panel) return;
    if (DPDialogPanelWCClass && [window.windowController isKindOfClass:DPDialogPanelWCClass])
        DPHidePromptWindow(window, panel);
    else
        DPHideOverlayHost(panel);
    DPScheduleDecline(panel, decline);
}

void DPDismissConnectAppPrompts(void) {
    if (!DPDialogPanelClass || !DPSuppressConnectPrompts()) return;
    for (NSWindow *window in NSApp.windows.copy) {
        DPDismissInWindow(window);
        for (NSWindow *sheet in window.sheets.copy) DPDismissInWindow(sheet);
    }
}

static void DPInstallHideConnectAppPrompts(void) {
    DPDialogPanelClass = objc_getClass(DPDiaDialogPanel);
    DPDialogButtonClass = objc_getClass(DPDiaDialogButton);
    DPDialogPanelVCClass = objc_getClass(DPDiaDialogPanelVC);
    DPDialogPanelWCClass = objc_getClass(DPDiaDialogPanelWC);
    DPHookClass(NSWindow.class, @selector(beginSheet:completionHandler:), (IMP)DPWindow_beginSheet);
    DPHookClass(NSWindow.class, @selector(makeKeyAndOrderFront:), (IMP)DPWindow_makeKeyAndOrderFront);
    DPHookClass(NSWindow.class, @selector(orderFront:), (IMP)DPWindow_orderFront);
    DPHook(DPDiaDialogPanelVC, @selector(viewDidLoad), (IMP)DPDialogPanelVC_viewDidLoad);
    DPHook(DPDiaDialogPanel, @selector(viewDidMoveToWindow), (IMP)DPDialogPanel_viewDidMoveToWindow);
    DPHook(DPDiaDialogPanel, @selector(handleButton:), (IMP)DPDialogPanel_handleButton);
    DPHostHides(DPDiaAppsUpsellBar);
}

static void DPApplyHideConnectAppPrompts(DPPatch *patch) {
    DPApplyHides(patch);
    if (DPSuppressConnectPrompts()) DPDismissConnectAppPrompts();
}

DP_PATCH(DPHideConnectAppPrompts) {
    .key = @"hideConnectAppPrompts",
    .order = 220,
    .title = @"Hide Connect App Prompt",
    .detail = @"Stop the “Connect to Dia?” prompts and app upsell bars that ask to link logged-in apps for Chat. You can still connect apps from Dia’s Apps settings.",
    .symbol = @"app.connected.to.app.below.fill link.circle.fill",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .group = @"aiPrompts",
    .coveredBy = @"turnOffAI",
    .classes = DPClasses(DPDiaDialogPanel, DPDiaDialogButton, DPDiaDialogPanelVC, DPDiaDialogPanelWC),
    .hides = DPIsSingleAppUpsellBar,
    .install = DPInstallHideConnectAppPrompts,
    .apply = DPApplyHideConnectAppPrompts,
};
