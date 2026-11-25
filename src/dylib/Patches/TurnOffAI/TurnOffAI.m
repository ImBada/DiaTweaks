#import "TurnOffAI.h"
#import "Patches/HideConnectAppPrompts/HideConnectAppPrompts.h"
#import "Updates/Updates.h"

#define DPDiaCapabilitiesToolbar "_TtC23AssistantCapabilitiesUI32AssistantCapabilitiesToolbarView"
#define DPDiaTabCardActions      "_TtC5TabUI21TabPopoverActionsView"
#define DPDiaPlaceholderText     "_TtC5ARCUI23TextViewWithPlaceholder"
#define DPDiaChatSidebar         "_TtC6Window30AssistantSidebarViewController"

BOOL DPIsAITitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || [title hasPrefix:@"Chat with Support"]) return NO;
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = [NSSet setWithArray:@[ @"Chat…", @"New Chat", @"Focus Chat", @"Send Chat Prompt Now", @"Open Daily Brief", @"Personalize Dia", @"Chat events", @"Daily report" ]];
    });
    if ([titles containsObject:title]) return YES;
    NSStringCompareOptions prefix = NSCaseInsensitiveSearch | NSAnchoredSearch;
    return [title rangeOfString:@"chat with " options:prefix].location != NSNotFound
        || [title rangeOfString:@"ask dia" options:prefix].location != NSNotFound;
}

static BOOL DPIsAIView(NSView *view) {
    return DPIsChatButton(view) || DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell)
        || DPIsKind(view, DPDiaSkillsSuggestions) || DPIsKind(view, DPDiaPersonalizeButton) || DPIsKind(view, DPDiaChatUsage)
        || DPIsKind(view, DPDiaCapabilityButton) || DPIsKind(view, DPDiaTrialButton) || DPIsSingleAppUpsellBar(view);
}

static void DPHost_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPHost_layout, self);
}

static NSHashTable<NSView *> *DPMorningBriefs;
static char DPBriefHiddenKey;

static void DPHideBrief(NSView *section) {
    if (DPTurnOffAI.on && !section.hidden) {
        section.hidden = YES;
        DPSet(section, &DPBriefHiddenKey, @YES);
    } else if (!DPTurnOffAI.on && DPGet(section, &DPBriefHiddenKey)) {
        section.hidden = NO;
        DPSet(section, &DPBriefHiddenKey, nil);
    }
}

static void DPSettingsHeader_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSettingsHeader_layout, self);
    NSTextField *title = (NSTextField *)DPFindView(self, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    if (![title.stringValue isEqual:@"Morning Brief"] || !self.superview) return;
    [DPMorningBriefs addObject:self.superview];
    DPHideBrief(self.superview);
}

static NSHashTable<NSViewController *> *DPChatSidebars;

static void DPCloseChat(NSViewController *sidebar) {
    if (!DPTurnOffAI.on) return;
    NSView *hide = DPFindView(sidebar.view, ^BOOL(NSView *view) { return DPHasLabel(view, @"Hide chat"); });
    if (!hide.isHiddenOrHasHiddenAncestor) [hide accessibilityPerformPress];
}

static void DPChatSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPChatSidebar_viewWillLayout, self);
    [DPChatSidebars addObject:self];
    if (DPTurnOffAI.on) dispatch_async(dispatch_get_main_queue(), ^{ DPCloseChat(self); });
}

static NSHashTable<NSTextView *> *DPPlaceholderViews;

static NSAttributedString *DPPlaceholder_get(NSTextView *self, SEL _cmd) {
    NSAttributedString *dia = DPCallOriginal(DPPlaceholder_get, self);
    [DPPlaceholderViews addObject:self];
    if (!DPTurnOffAI.on || ![dia.string.lowercaseString hasPrefix:@"ask "]) return dia;
    NSMutableAttributedString *ours = [dia mutableCopy];
    [ours replaceCharactersInRange:NSMakeRange(0, ours.length) withString:@"Search or enter address"];
    return ours;
}

static NSHashTable<NSMenuItem *> *DPAIItems;
static NSSet<NSString *> *DPAIShortcuts;
static BOOL DPAIPlainShortcuts;
static id DPAIKeyMonitor;
static char DPDiaHiddenKey;

static void DPItem_setHidden(NSMenuItem *self, SEL _cmd, BOOL hidden) {
    BOOL ai = [DPAIItems containsObject:self];
    if (ai) DPSet(self, &DPDiaHiddenKey, @(hidden));
    DPCallOriginal(DPItem_setHidden, self, hidden || (ai && DPTurnOffAI.on));
}

static void DPItem_setKeyEquivalent(NSMenuItem *self, SEL _cmd, NSString *key) {
    DPCallOriginal(DPItem_setKeyEquivalent, self, key);
    if ([DPAIItems containsObject:self]) DPAIShortcuts = nil;
}

static void DPItem_setKeyEquivalentModifierMask(NSMenuItem *self, SEL _cmd, NSEventModifierFlags mask) {
    DPCallOriginal(DPItem_setKeyEquivalentModifierMask, self, mask);
    if ([DPAIItems containsObject:self]) DPAIShortcuts = nil;
}

static void DPTrack(NSMenuItem *item) {
    if (!DPIsAITitle(item.title)) return;
    if (![DPAIItems containsObject:item]) {
        DPSet(item, &DPDiaHiddenKey, @(item.hidden));
        [DPAIItems addObject:item];
    }
    DPAIShortcuts = nil;
    BOOL diaHidden = [DPGet(item, &DPDiaHiddenKey) boolValue];
    BOOL wantHidden = diaHidden || DPTurnOffAI.on;
    if (item.hidden != wantHidden) item.hidden = diaHidden;
}

static void DPTrackMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        DPTrack(item);
        if (item.submenu) DPTrackMenu(item.submenu);
    }
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    DPTrack(item);
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    DPTrack(item);
}

static const NSEventModifierFlags DPModifiers = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
static const NSEventModifierFlags DPChordModifiers = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption;

static NSString *DPSignShortcut(NSEventModifierFlags mods, NSString *key) {
    return key.length ? [NSString stringWithFormat:@"%lx:%@", (unsigned long)(mods & DPModifiers), key.lowercaseString] : nil;
}

static NSSet<NSString *> *DPAIShortcutSet(void) {
    if (DPAIShortcuts) return DPAIShortcuts;
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    BOOL plain = NO;
    for (NSMenuItem *item in DPAIItems) {
        NSString *signedKey = DPSignShortcut(item.keyEquivalentModifierMask, item.keyEquivalent);
        if (!signedKey) continue;
        [set addObject:signedKey];
        if (!(item.keyEquivalentModifierMask & DPChordModifiers)) plain = YES;
    }
    DPAIPlainShortcuts = plain;
    return DPAIShortcuts = [set copy];
}

// Dia dispatches shortcuts ahead of menus, so hidden AI items must be blocked here.
static BOOL DPIsAIShortcut(NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & DPModifiers;
    NSSet<NSString *> *shortcuts = DPAIShortcutSet();
    if ((mods & DPChordModifiers) || DPAIPlainShortcuts) {
        NSString *signedKey = DPSignShortcut(mods, event.charactersIgnoringModifiers);
        if (signedKey && [shortcuts containsObject:signedKey]) return YES;
    }
    if ((event.keyCode != 36 && event.keyCode != 76) || mods != (NSEventModifierFlagCommand | NSEventModifierFlagControl)) return NO;
    return [NSStringFromClass([event.window.firstResponder class]) hasPrefix:@"_TtCC15BoostCommandBar"];
}

static BOOL gCutOff;

static void DPCutOffAIServers(void) {
    gCutOff = DPTurnOffAI.on;
    NSMutableArray<NSString *> *rules = [NSMutableArray array];
    for (NSString *host in @[ @"ai-service", @"aiproxy", @"webresultproxy", @"websearch", @"artifactcdn", @"tools-cache" ])
        [rules addObject:[NSString stringWithFormat:@"MAP %@.diabrowser.engineering ~NOTFOUND", host]];
    NSString *flag = [@"--host-resolver-rules=" stringByAppendingString:[rules componentsJoinedByString:@", "]];
    if (gCutOff) DPAddLaunchFlag(flag);
    else DPDropLaunchFlag(flag);
}

static void DPOfferRelaunch(DPPatch *patch) {
    if (DPTesting || patch->on == gCutOff || patch->on != DPSavedOn(patch)) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to cut off its AI servers" : @"Relaunch Dia to reconnect its AI servers";
    alert.informativeText = patch->on ? @"Until then, AI is hidden, but Dia can still reach its AI servers." : @"Until then, chat can’t reach them.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

static void DPSyncAIMonitor(void) {
    DPSyncMonitor(&DPAIKeyMonitor, DPTurnOffAI.on, NSEventMaskKeyDown, ^NSEvent *(NSEvent *event) {
        return DPTurnOffAI.on && !DPShortcutRecording() && DPIsAIShortcut(event) ? nil : event;
    });
}

static void DPInstallTurnOffAI(void) {
    DPCutOffAIServers();
    DPAIItems = [NSHashTable weakObjectsHashTable];
    DPAIShortcuts = nil;
    DPPlaceholderViews = [NSHashTable weakObjectsHashTable];
    DPMorningBriefs = [NSHashTable weakObjectsHashTable];
    DPChatSidebars = [NSHashTable weakObjectsHashTable];
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPHookClass(NSMenuItem.class, @selector(setHidden:), (IMP)DPItem_setHidden);
    DPHookClass(NSMenuItem.class, @selector(setKeyEquivalent:), (IMP)DPItem_setKeyEquivalent);
    DPHookClass(NSMenuItem.class, @selector(setKeyEquivalentModifierMask:), (IMP)DPItem_setKeyEquivalentModifierMask);
    DPHook(DPDiaCapabilitiesToolbar, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaTabCardActions, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaSettingsHeader, @selector(layout), (IMP)DPSettingsHeader_layout);
    DPHook(DPDiaPlaceholderText, @selector(placeholderAttributedString), (IMP)DPPlaceholder_get);
    DPHook(DPDiaChatSidebar, @selector(viewWillLayout), (IMP)DPChatSidebar_viewWillLayout);
    DPInstallAIRows();
    DPSyncAIMonitor();
    DPOnLaunch(^{ DPTrackMenu(NSApp.mainMenu); });
}

static void DPApplyTurnOffAI(DPPatch *patch) {
    DPApplyHides(patch);
    DPAIShortcuts = nil;
    DPSyncAIMonitor();
    for (NSMenuItem *item in DPAIItems.allObjects) DPTrack(item);
    for (NSTextView *view in DPPlaceholderViews.allObjects) view.needsDisplay = YES;
    for (NSView *section in DPMorningBriefs.allObjects) DPHideBrief(section);
    for (NSViewController *sidebar in DPChatSidebars.allObjects) DPCloseChat(sidebar);
    DPApplyAIRows();
    if (patch->on) DPDismissConnectAppPrompts();
    DPOfferRelaunch(patch);
}

DP_PATCH(DPTurnOffAI) {
    .key = @"turnOffAI",
    .order = 95,
    .section = @"AI",
    .title = @"Turn Off AI",
    .detail = @"Turn off every AI feature in Dia: chat and its buttons, menus and shortcuts, Skills, Ask Dia, Morning Brief, and Settings’ Apps and Skills. After a relaunch, Dia can’t reach its AI servers either. To send questions to search, set Address Bar to Prefer Search Engine in Advanced.",
    .symbol = @"bubble.left.and.exclamationmark.bubble.right.fill bubble.left.fill",
    .tint = @"systemPurpleColor",
    .hides = DPIsAIView,
    .relaunch = YES,
    .install = DPInstallTurnOffAI,
    .apply = DPApplyTurnOffAI,
};
