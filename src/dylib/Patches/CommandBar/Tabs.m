#import "Patches/CommandBar/Tabs.h"

id DPScriptWindow(NSWindow *window) {
    NSString *identifier = window.identifier;
    if (!identifier) return nil;
    id windows = DPValueForKey(NSApp.delegate, @"appleScriptWindows");
    if (![windows isKindOfClass:NSArray.class]) return nil;
    for (id scripted in windows)
        if ([DPValueForKey(scripted, @"windowId") isEqual:identifier]) return scripted;
    return nil;
}

id DPScriptTabIn(id scriptWindow, NSString *tabID) {
    if (!scriptWindow || !tabID) return nil;
    for (id tab in DPScriptTabs(scriptWindow))
        if ([DPValueForKey(tab, @"tabId") isEqual:tabID]) return tab;
    return nil;
}

id DPScriptTab(NSWindow *window, NSString *tabID) { return tabID ? DPScriptTabIn(DPScriptWindow(window), tabID) : nil; }

id DPScriptTabInAnyProfile(id scriptWindow, NSString *tabID) {
    if (!scriptWindow || !tabID) return nil;
    id profiles = DPValueForKey(scriptWindow, @"appleScriptProfiles");
    if (![profiles isKindOfClass:NSArray.class]) return nil;
    for (id profile in profiles) {
        id tab = DPScriptTabIn(profile, tabID);
        if (tab) return tab;
    }
    return nil;
}

id DPScriptProfileHolding(id scriptWindow, NSString *tabID) {
    id profiles = tabID ? DPValueForKey(scriptWindow, @"appleScriptProfiles") : nil;
    if (![profiles isKindOfClass:NSArray.class]) return nil;
    for (id profile in profiles)
        if (DPScriptTabIn(profile, tabID)) return profile;
    return nil;
}

NSString *DPTabID(id tab) { return DPValueForKey(tab, @"tabId"); }
NSString *DPActiveTabIDIn(id scriptWindow) { return DPTabID(DPValueForKey(scriptWindow, @"activeTab")); }
NSString *DPActiveTabID(NSWindow *window) { return DPActiveTabIDIn(DPScriptWindow(window)); }
void DPFocusTab(id tab) { if ([tab respondsToSelector:@selector(focus:)]) [tab performSelector:@selector(focus:) withObject:nil]; }
static NSInteger DPOwnCloses;
static CFTimeInterval DPOwnClosesLapse;

void DPMarkOwnClose(void) {
    DPOwnCloses++;
    DPOwnClosesLapse = CACurrentMediaTime() + 1;
}

BOOL DPTakeOwnClose(void) {
    if (CACurrentMediaTime() > DPOwnClosesLapse) DPOwnCloses = 0;
    if (DPOwnCloses <= 0) return NO;
    DPOwnCloses--;
    return YES;
}

void DPCloseTab(id tab) {
    if (!tab || ![tab respondsToSelector:@selector(close:)]) return;
    DPMarkOwnClose();
    [tab performSelector:@selector(close:) withObject:nil];
}
