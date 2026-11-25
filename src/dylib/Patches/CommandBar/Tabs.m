#import "Patches/CommandBar/Tabs.h"
#import <pthread.h>

@interface DPScriptWindowMemo : NSObject {
@public
    __weak id delegate;
    NSString *identifier;
    id scripted;
}
@end

@implementation DPScriptWindowMemo
@end

static NSMapTable<NSWindow *, DPScriptWindowMemo *> *DPScriptWindowCache;
static BOOL DPScriptWindowClearArmed;

static void DPClearScriptWindowCache(void) {
    [DPScriptWindowCache removeAllObjects];
    DPScriptWindowClearArmed = NO;
}

static BOOL DPMemoMatchesDelegate(id delegate, DPScriptWindowMemo *memo, NSString *identifier) {
    if (!memo || memo->delegate != delegate || ![memo->identifier isEqualToString:identifier]) return NO;
    void *slot = DPIvar(delegate, "_appleScriptWindows") ?: DPIvar(delegate, "appleScriptWindows");
    if (!slot) return YES;
    id stored = *(__unsafe_unretained id *)slot;
    return [stored isKindOfClass:NSArray.class] && [(NSArray *)stored indexOfObjectIdenticalTo:memo->scripted] != NSNotFound
        && [[DPValueForKey(memo->scripted, @"windowId") description] isEqualToString:identifier];
}

id DPScriptWindow(NSWindow *window) {
    NSString *identifier = window.identifier;
    id delegate = NSApp.delegate;
    if (!identifier || !delegate) return nil;
    BOOL onMain = pthread_main_np() != 0;
    if (onMain) {
        if (!DPScriptWindowCache) {
            DPScriptWindowCache = [NSMapTable weakToStrongObjectsMapTable];
            CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopExit, true, 0,
                ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { DPClearScriptWindowCache(); });
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
            CFRelease(observer);
        }
        DPScriptWindowMemo *memo = [DPScriptWindowCache objectForKey:window];
        if (DPMemoMatchesDelegate(delegate, memo, identifier)) return memo->scripted;
    }
    id windows = DPValueForKey(delegate, @"appleScriptWindows");
    if (![windows isKindOfClass:NSArray.class]) return nil;
    for (id scripted in windows)
        if ([DPValueForKey(scripted, @"windowId") isEqual:identifier]) {
            if (onMain) {
                DPScriptWindowMemo *memo = [DPScriptWindowMemo new];
                memo->delegate = delegate;
                memo->identifier = [identifier copy];
                memo->scripted = scripted;
                [DPScriptWindowCache setObject:memo forKey:window];
                if (!DPScriptWindowClearArmed) {
                    DPScriptWindowClearArmed = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{ DPClearScriptWindowCache(); });
                }
            }
            return scripted;
        }
    if (onMain) [DPScriptWindowCache removeObjectForKey:window];
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

// 1 when the window lists the tab, 0 when it lists others, -1 when Dia isn't saying (no scripting window, or none listing a tab, as mid-swipe).
NSInteger DPTabListing(id scriptWindow, NSString *tabID) {
    id profiles = DPValueForKey(scriptWindow, @"appleScriptProfiles");
    if (!tabID || ![profiles isKindOfClass:NSArray.class]) return -1;
    NSUInteger listed = 0;
    for (id profile in profiles) {
        if (DPScriptTabIn(profile, tabID)) return 1;
        listed += DPScriptTabs(profile).count;
    }
    return listed ? 0 : -1;
}

NSString *DPTabID(id tab) {
    NSString *identifier = DPValueForKey(tab, @"tabId");
    return [identifier isKindOfClass:NSString.class] && identifier.length ? identifier : nil;
}
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
