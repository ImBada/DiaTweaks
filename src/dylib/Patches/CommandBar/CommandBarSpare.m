#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/HideTab.h"
#import <objc/message.h>

static char DPSpareKey;

static NSString *const DPSparesKey = @"commandBarSpares";

// Persist parked/open-bar tab IDs so restored empty spares are closed on next launch (never a space's only tab).
void DPNoteSpare(NSString *tabID, BOOL parked) {
    if (!tabID) return;
    NSArray *noted = [DPSettings() arrayForKey:DPSparesKey] ?: @[];
    BOOL keep = parked && DPSparesOn();
    if (keep == [noted containsObject:tabID]) return;
    NSMutableArray *spares = noted.mutableCopy;
    if (keep) [spares addObject:tabID];
    else [spares removeObject:tabID];
    [DPSettings() setObject:spares forKey:DPSparesKey];
}

void DPCloseLeftSpares(NSArray<NSString *> *left, BOOL last) {
    if (!DPSparesOn()) return;
    for (NSString *tabID in left) {
        id tab = nil, space = nil, foundScript = nil;
        NSWindow *foundWindow = nil;
        for (NSWindow *window in NSApp.windows) {
            id scriptWindow = DPScriptWindow(window);
            id profiles = DPValueForKey(scriptWindow, @"appleScriptProfiles");
            if (![profiles isKindOfClass:NSArray.class]) continue;
            for (id profile in profiles)
                if ((tab = DPScriptTabIn(profile, tabID))) {
                    space = profile; foundScript = scriptWindow; foundWindow = window;
                    break;
                }
            if (tab) break;
        }
        if (tab && [DPTabID(DPSpareIn(foundWindow).openedTab) isEqual:tabID]) continue;
        if (tab && [DPActiveTabIDIn(foundScript) isEqual:tabID]) {
            DPCommandBarOverlay *overlay = DPGet(foundWindow, &DPOverlayKey);
            BOOL hasText = overlay && [DPTabID(overlay.openedTab) isEqual:tabID] && DPBarText(overlay).string.length > 0;
            if (hasText || CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType) < 5) {
                if (last) DPNoteSpare(tabID, NO);
                continue;
            }
        }
        NSString *url = [DPValueForKey(tab, @"URL") description];
        id spaceTabs = DPValueForKey(space, @"appleScriptTabs");
        if (tab && !url.length && [spaceTabs isKindOfClass:NSArray.class] && [spaceTabs count] > 1) DPCloseTab(tab);
        if (tab || last) DPNoteSpare(tabID, NO);
    }
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
        NSString *url = [DPValueForKey(tab, @"URL") description];
        id profileTabs = DPValueForKey(profile, @"appleScriptTabs");
        if (!url.length && [profileTabs isKindOfClass:NSArray.class] && [profileTabs count] > 1) DPCloseTab(tab);
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

BOOL DPParkSpare(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    NSString *tabID = DPTabID(overlay.openedTab);
    if (!window || !DPSparesOn() || !overlay.returnTab || DPGet(window, &DPSpareKey) || !DPHiddenTab(tabID) || DPHasStrip(window)) return NO;
    id scriptWindow = DPScriptWindow(window);
    if (!DPScriptTabIn(scriptWindow, tabID) || !DPScriptTabIn(scriptWindow, DPTabID(overlay.returnTab))) return NO;
    [overlay.watch invalidate];
    if (overlay.keyMonitor) [NSEvent removeMonitor:overlay.keyMonitor];
    overlay.keyMonitor = nil;
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
    overlay.hidden = YES;
    // Clear now so Dia shrinks suggestions out of sight instead of when reopened.
    NSTextView *text = DPBarText(overlay);
    if (!DPCommandBarKeepText.on && text.string.length) [text insertText:@"" replacementRange:NSMakeRange(0, text.string.length)];
    if (DPGet(window, &DPOverlayKey) == overlay) DPSet(window, &DPOverlayKey, nil);
    DPSet(window, &DPSpareKey, overlay);
    DPNoteSpare(tabID, YES);
    DPParkTab(tabID, YES);
    DPStandInForTab(window, tabID);
    NSResponder *typing = window.firstResponder;
    if ([typing isKindOfClass:NSView.class] && ![(NSView *)typing isDescendantOf:overlay]) return YES;
    Class card = NSClassFromString(@"DPPeekCard");
    NSView *peek = card ? DPFindView(window.contentView, ^BOOL(NSView *view) {
        return [view isKindOfClass:card] && !view.isHiddenOrHasHiddenAncestor;
    }) : nil;
    NSView *web = peek ? DPFindView(peek, ^BOOL(NSView *view) { return DPIsKind(view, "RenderWidgetHostViewCocoa") && !view.isHiddenOrHasHiddenAncestor; }) : nil;
    SEL hostSel = NSSelectorFromString(@"host");
    if (!web && peek && [peek respondsToSelector:hostSel]) {
        id host = ((id (*)(id, SEL))objc_msgSend)(peek, hostSel);
        if ([host isKindOfClass:NSView.class] && !((NSView *)host).isHiddenOrHasHiddenAncestor) web = host;
    }
    if (!web) web = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, "RenderWidgetHostViewCocoa") && !view.isHiddenOrHasHiddenAncestor; });
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
        id tabs = DPValueForKey(scriptWindow, @"appleScriptTabs");
        if (![tabs isKindOfClass:NSArray.class] || [tabs count] < 2) {
            if (weakPage.window) DPMakeBlank(weakPage, tabID, nil);
            return;
        }
        [DPBlanks(weakWindow) removeObject:tabID];
        DPCloseTab(tab);
    });
    return YES;
}
