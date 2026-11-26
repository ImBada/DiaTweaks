#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/HideTab.h"
#import <objc/message.h>

static char DPSpareKey;

static NSString *const DPSparesKey = @"commandBarSpares";
static NSString *const DPOpenTabsKey = @"commandBarOpenTabs";

static void DPNoteTab(NSString *key, NSString *tabID, BOOL keep) {
    if (!tabID) return;
    NSArray *noted = [DPSettingsDefaults() arrayForKey:key] ?: @[];
    if (keep == [noted containsObject:tabID]) return;
    NSMutableArray *tabs = noted.mutableCopy;
    if (keep) [tabs addObject:tabID];
    else [tabs removeObject:tabID];
    [DPSettingsDefaults() setObject:tabs forKey:key];
}

void DPNoteSpare(NSString *tabID, BOOL parked) {
    DPNoteTab(DPSparesKey, tabID, parked && DPSparesOn());
    if (!parked) DPNoteTab(DPOpenTabsKey, tabID, NO);
}

void DPNoteOpenTab(NSString *tabID, BOOL open) { DPNoteTab(DPOpenTabsKey, tabID, open && DPHiding()); }

static id DPLeftTab(NSString *tabID, id *space, id *scriptWindow, NSWindow **window) {
    for (NSWindow *candidate in NSApp.windows) {
        id scripted = DPScriptWindow(candidate);
        id profiles = DPValueForKey(scripted, @"appleScriptProfiles");
        if (![profiles isKindOfClass:NSArray.class]) continue;
        for (id profile in profiles) {
            id tab = DPScriptTabIn(profile, tabID);
            if (!tab) continue;
            *space = profile;
            *scriptWindow = scripted;
            *window = candidate;
            return tab;
        }
    }
    return nil;
}

static BOOL DPClosableBlank(id tab, id space) {
    return tab && ![DPValueForKey(tab, @"URL") description].length && DPScriptTabs(space).count > 1;
}

static void DPCloseLeft(NSArray<NSString *> *left, BOOL last, void (^forget)(NSString *tabID), void (^close)(NSString *tabID, id tab, NSWindow *window)) {
    for (NSString *tabID in left) {
        id space = nil, foundScript = nil;
        NSWindow *foundWindow = nil;
        id tab = DPLeftTab(tabID, &space, &foundScript, &foundWindow);
        if (tab && [DPTabID(DPSpareIn(foundWindow).openedTab) isEqual:tabID]) continue;
        if (tab && [DPActiveTabIDIn(foundScript) isEqual:tabID]) {
            DPCommandBarOverlay *overlay = DPGet(foundWindow, &DPOverlayKey);
            BOOL hasText = overlay && [DPTabID(overlay.openedTab) isEqual:tabID] && DPBarText(overlay).string.length > 0;
            if (hasText || CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType) < 5) {
                if (last) forget(tabID);
                continue;
            }
        }
        if (DPClosableBlank(tab, space)) close(tabID, tab, foundWindow);
        if (tab || last) forget(tabID);
    }
}

void DPCloseLeftOpenTabs(NSArray<NSString *> *left, BOOL last) {
    if (!DPHiding()) return;
    DPCloseLeft(left, last, ^(NSString *tabID) { DPNoteOpenTab(tabID, NO); }, ^(NSString *tabID, id tab, NSWindow *window) {
        DPHideBlank(tabID, YES, window);
        DPParkTab(tabID, YES);
        DPCloseTab(tab);
        DPShowTabRow(tabID, NO);
    });
}

void DPCloseLeftSpares(NSArray<NSString *> *left, BOOL last) {
    if (!DPSparesOn()) return;
    DPCloseLeft(left, last, ^(NSString *tabID) { DPNoteSpare(tabID, NO); }, ^(NSString *tabID, id tab, NSWindow *window) { DPCloseTab(tab); });
}

// Dia restores tabs over the first few seconds, so hide and close the bar's leftovers now and again until it settles.
void DPCloseLeftBarTabs(void) {
    if (!DPHiding()) {
        // Nothing hides these tabs any more, so forget them rather than closing tabs the user can see.
        [DPSettingsDefaults() setObject:@[] forKey:DPOpenTabsKey];
        return;
    }
    NSArray *open = [DPSettingsDefaults() arrayForKey:DPOpenTabsKey];
    NSArray *spares = [DPSettingsDefaults() arrayForKey:DPSparesKey];
    if (!open.count && !spares.count) return;
    DPCloseLeftOpenTabs(open, NO);
    DPCloseLeftSpares(spares, NO);
    for (int delay = 3; (open.count || spares.count) && delay <= 12; delay += 9)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            DPCloseLeftOpenTabs(open, delay > 3);
            DPCloseLeftSpares(spares, delay > 3);
        });
}

void DPDropSpare(NSWindow *window) {
    DPCommandBarOverlay *spare = DPGet(window, &DPSpareKey);
    if (!spare) return;
    DPSet(window, &DPSpareKey, nil);
    NSString *tabID = DPTabID(spare.openedTab);
    DPNoteSpare(tabID, NO);
    DPWantSpare();
    DPDismiss(spare, YES);
    id scriptWindow = DPScriptWindow(window);
    id profiles = DPValueForKey(scriptWindow, @"appleScriptProfiles");
    if (!scriptWindow || !tabID || ![profiles isKindOfClass:NSArray.class]) return;
    for (id profile in profiles) {
        id tab = DPScriptTabIn(profile, tabID);
        if (!tab) continue;
        if (DPClosableBlank(tab, profile)) DPCloseBarTab(window, tab);
        return;
    }
}

void DPForgetSpare(NSWindow *window) {
    DPCommandBarOverlay *spare = DPGet(window, &DPSpareKey);
    if (!spare) return;
    DPSet(window, &DPSpareKey, nil);
    DPNoteSpare(DPTabID(spare.openedTab), NO);
    DPWantSpare();
    DPDismiss(spare, NO);
}

static NSView *DPVisibleWebView(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, "RenderWidgetHostViewCocoa") && !view.isHiddenOrHasHiddenAncestor; });
}

BOOL DPParkSpare(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    NSString *tabID = DPTabID(overlay.openedTab);
    if (!window || !DPSparesOn() || !overlay.returnTab || DPGet(window, &DPSpareKey) || !DPHiddenTab(tabID) || DPHasStrip(window)) return NO;
    id scriptWindow = DPScriptWindow(window);
    if (!DPScriptTabIn(scriptWindow, tabID) || !DPScriptTabIn(scriptWindow, DPTabID(overlay.returnTab))) return NO;
    DPStopWatching(overlay);
    DPRemoveShade(overlay);
    overlay.hidden = YES;
    // Clear now so Dia shrinks suggestions out of sight rather than on reopen.
    NSTextView *text = DPBarText(overlay);
    if (!DPCommandBarKeepText.on && text.string.length) [text insertText:@"" replacementRange:NSMakeRange(0, text.string.length)];
    if (DPGet(window, &DPOverlayKey) == overlay) DPSet(window, &DPOverlayKey, nil);
    DPSet(window, &DPSpareKey, overlay);
    DPNoteSpare(tabID, YES);
    DPNoteOpenTab(tabID, NO);
    DPParkTab(tabID, YES);
    DPStandInForTab(window, tabID);
    NSResponder *typing = window.firstResponder;
    if ([typing isKindOfClass:NSView.class] && ![(NSView *)typing isDescendantOf:overlay]) return YES;
    NSView *peek = DPVisiblePeek(window);
    NSView *web = DPVisibleWebView(peek);
    SEL hostSel = NSSelectorFromString(@"host");
    if (!web && peek && [peek respondsToSelector:hostSel]) {
        id host = ((id (*)(id, SEL))objc_msgSend)(peek, hostSel);
        if ([host isKindOfClass:NSView.class] && !((NSView *)host).isHiddenOrHasHiddenAncestor) web = host;
    }
    if (!web) web = DPVisibleWebView(window.contentView);
    [window makeFirstResponder:web];
    return YES;
}

BOOL DPShowSpare(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPSpareKey);
    if (!overlay) return NO;
    NSString *tabID = DPTabID(overlay.openedTab);
    id scriptWindow = DPScriptWindow(window), front = DPValueForKey(scriptWindow, @"activeTab");
    if ([DPTabID(front) isEqual:tabID]) {
        NSView *page = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNewTabPage) && !view.isHiddenOrHasHiddenAncestor; });
        DPAdoptSpare(window, page);
        return NO;
    }
    if (!DPSparesOn() || !DPHiddenTab(tabID) || !front || overlay.panel.superview != overlay || !DPScriptTabIn(scriptWindow, tabID) || DPHasStrip(window)) {
        DPDropSpare(window);
        return NO;
    }
    DPSet(window, &DPSpareKey, nil);
    DPWantSpare();
    DPFreezeLists(window);
    DPNoteSpare(tabID, NO);
    DPNoteOpenTab(tabID, YES);
    DPParkTab(tabID, NO);
    DPSet(window, &DPOverlayKey, overlay);
    overlay.returnTab = front;
    overlay.picked = NO;
    overlay.startURL = DPValueForKey(overlay.openedTab, @"URL");
    NSTextView *text = DPBarText(overlay);
    if (DPCommandBarKeepText.on) [text selectAll:nil];
    else [text insertText:@"" replacementRange:NSMakeRange(0, text.string.length)];
    overlay.hidden = NO;
    DPShowShade(overlay);
    overlay.needsLayout = YES;
    DPFocusBar(overlay);
    overlay.keyMonitor = DPWatchKeys(overlay);
    DPStandInFor(window, tabID);
    DPWatch(overlay);
    return YES;
}

DPCommandBarOverlay *DPSpareIn(NSWindow *window) { return DPGet(window, &DPSpareKey); }

BOOL DPAdoptSpare(NSWindow *window, NSView *page) {
    DPCommandBarOverlay *spare = DPSpareIn(window);
    NSString *tabID = DPTabID(spare.openedTab);
    if (!spare || !page.window || ![DPActiveTabID(window) isEqual:tabID]) return NO;
    DPSet(window, &DPSpareKey, nil);
    DPNoteSpare(tabID, NO);
    DPDismiss(spare, YES);
    DPMakeBlank(page, tabID, nil);
    DPWantSpare();
    // Defer closing: closing a tab Dia is still activating crashes it.
    __weak NSWindow *weakWindow = window;
    __weak NSView *weakPage = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weakWindow || DPGet(weakWindow, &DPOverlayKey)) return;
        id scriptWindow = DPScriptWindow(weakWindow), tab = DPScriptTabIn(scriptWindow, tabID);
        if (!tab || [DPValueForKey(tab, @"URL") description].length) return;
        if (DPScriptTabs(scriptWindow).count < 2) {
            if (weakPage.window) DPMakeBlank(weakPage, tabID, nil);
            return;
        }
        [DPBlanks(weakWindow) removeObject:tabID];
        DPCloseBarTab(weakWindow, tab);
    });
    return YES;
}
