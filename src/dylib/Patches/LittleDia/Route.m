#import "LittleDia.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import <Carbon/Carbon.h>

static BOOL DPOnScreens(NSRect frame, NSArray<NSValue *> *screens) {
    if (NSIsEmptyRect(frame)) return NO;
    for (NSValue *screen in screens)
        if (NSContainsRect(screen.rectValue, frame)) return YES;
    return NO;
}

static NSRect DPLittleDiaFrame(void) {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    NSRect left = DPLittleDiaRemember.on ? DPLittleDiaSavedFrame() : NSZeroRect;
    if (DPOnScreens(left, [screens valueForKey:@"frame"])) return left;
    NSScreen *screen = NSScreen.mainScreen;
    NSPoint mouse = NSEvent.mouseLocation;
    for (NSScreen *each in screens)
        if (NSMouseInRect(mouse, each.frame, NO)) {
            screen = each;
            break;
        }
    NSRect visible = screen.visibleFrame;
    NSSize wanted = DPLittleDiaSize();
    NSSize size = NSMakeSize(round(MIN(wanted.width, NSWidth(visible) * 0.95)), round(MIN(wanted.height, NSHeight(visible) * 0.95)));
    return NSMakeRect(round(NSMidX(visible) - size.width / 2), round(NSMidY(visible) - size.height / 2), size.width, size.height);
}

static NSURL *DPWebURLFromString(NSString *string) {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    NSURL *url = [NSURL URLWithString:trimmed encodingInvalidCharacters:YES];
    return DPIsWebURL(url) ? url : nil;
}

static BOOL DPIsFromSelf(NSAppleEventDescriptor *event) {
    return event && [event attributeDescriptorForKeyword:keySenderPIDAttr].int32Value == getpid();
}

static NSArray<NSURL *> *DPLittleDiaLinks(NSAppleEventDescriptor *event) {
    if (event.eventClass != kInternetEventClass || event.eventID != kAEGetURL) return nil;
    if (DPIsFromSelf(event) || (NSEvent.modifierFlags & NSEventModifierFlagOption)) return nil;
    NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
    if (!direct) return nil;
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    if (direct.descriptorType == typeAEList) {
        for (NSInteger i = 1, count = direct.numberOfItems; i <= count; i++) {
            NSURL *url = DPWebURLFromString([direct descriptorAtIndex:i].stringValue);
            if (url) [urls addObject:url];
        }
    } else {
        NSURL *url = DPWebURLFromString(direct.stringValue);
        if (url) [urls addObject:url];
    }
    return urls.count ? urls : nil;
}

// The worker drops requests after `until`, set before the link falls back to a tab, so no second copy opens.
static BOOL DPOpenFramed(NSURL *url, NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    NSString *address = url.absoluteString;
    if (!address) return NO;
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame) - NSMaxY(frame);
    long long until = llround((NSDate.date.timeIntervalSince1970 + DPLittleDiaWait - 0.5) * 1000);
    NSDictionary *request = @{@"action" : @"open", @"url" : address,
                              @"left" : @(llround(NSMinX(frame))), @"top" : @(llround(top)),
                              @"width" : @(llround(NSWidth(frame))), @"height" : @(llround(NSHeight(frame))),
                              @"until" : @(until)};
    if (!DPSendToLittleDia(request)) return NO;
    DPExpectLittleDiaWindow(frame, noted, missed, claimed);
    return YES;
}

static BOOL DPOpenInLittleDia(NSURL *url, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    return DPOpenFramed(url, DPLittleDiaFrame(), noted, missed, claimed);
}

static NSRect DPPageArea(NSWindow *window) {
    NSRect area = NSZeroRect;
    for (NSView *pane in DPFindViews(DPDiaContentPane))
        if (pane.window == window && !pane.hiddenOrHasHiddenAncestor)
            area = NSUnionRect(area, [window convertRectToScreen:[pane convertRect:pane.bounds toView:nil]]);
    return NSIsEmptyRect(area) ? window.frame : area;
}

static NSRect DPOverWindowFrame(NSWindow *source) {
    if (!source.visible) return DPLittleDiaFrame();
    // macOS keeps windows below the menu bar, which would take the margin from the bottom.
    NSRect page = DPPageArea(source), window = NSIntersectionRect(source.frame, (source.screen ?: NSScreen.mainScreen).visibleFrame);
    if (NSIsEmptyRect(window)) window = source.frame;
    if (DPTabsAtTop(source)) window.size.height = MIN(NSMaxY(window), NSMaxY(page)) - NSMinY(window);
    CGFloat width = MAX(round(NSWidth(page) * DPTabLinkWidth), 480), height = MAX(NSHeight(window) - 2 * DPTabLinkEdge, 360);
    return NSMakeRect(round(NSMidX(page) - width / 2), round(NSMidY(window) - height / 2), width, height);
}

// The stack is noted once, when the link arrives: noted again later it would find Dia in front.
static void DPOpenWhenReady(NSURL *url, NSDictionary *noted, void (^fallback)(void), int tries) {
    if (DPOpenInLittleDia(url, noted, fallback, nil)) return;
    if (tries <= 0 || !DPLittleDiaStarting()) return fallback();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPOpenWhenReady(url, noted, fallback, tries - 1); });
}

static NSAppleEventDescriptor *DPGetURLEvent(NSURL *url) {
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:kAEGetURL
                                                                    targetDescriptor:NSAppleEventDescriptor.nullDescriptor
                                                                            returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:url.absoluteString] forKeyword:keyDirectObject];
    return event;
}

static void DPOpenURLEvents_handle(id self, SEL _cmd, NSAppleEventDescriptor *event, NSAppleEventDescriptor *reply) {
    NSArray<NSURL *> *urls = DPLittleDia.on && !DPLittleDiaFollowRules.on ? DPLittleDiaLinks(event) : nil;
    if (!urls.count) return DPCallOriginal(DPOpenURLEvents_handle, self, event, reply);
    DPLinkArrived();
    NSDictionary *noted = DPNoteStackForLink();
    NSAppleEventDescriptor *kept = urls.count == 1 ? [event copy] : nil;  // The event is the system's and is gone once this returns.
    for (NSURL *url in urls) {
        NSAppleEventDescriptor *fallback = kept ?: DPGetURLEvent(url);
        DPOpenWhenReady(url, noted, ^{
            DPBringBackPutAway(nil);
            DPCallOriginal(DPOpenURLEvents_handle, self, fallback, [NSAppleEventDescriptor nullDescriptor]);
        }, 40);
    }
}

// Cold-launch or direct LaunchServices URL opens can reach AppDelegate before OpenURLEventManager registers.
static void DPAppDelegate_openURLs(id self, SEL _cmd, NSApplication *app, NSArray<NSURL *> *urls) {
    if (!DPLittleDia.on || DPLittleDiaFollowRules.on || (NSEvent.modifierFlags & NSEventModifierFlagOption)
        || DPIsFromSelf(NSAppleEventManager.sharedAppleEventManager.currentAppleEvent))
        return DPCallOriginal(DPAppDelegate_openURLs, self, app, urls);
    NSMutableArray<NSURL *> *web = [NSMutableArray array], *other = [NSMutableArray array];
    for (NSURL *url in urls) [(DPIsWebURL(url) ? web : other) addObject:url];
    if (!web.count) return DPCallOriginal(DPAppDelegate_openURLs, self, app, urls);
    if (other.count) DPCallOriginal(DPAppDelegate_openURLs, self, app, other);
    else DPLinkArrived();
    NSDictionary *noted = DPNoteStackForLink();
    for (NSURL *url in web) {
        DPOpenWhenReady(url, noted, ^{
            DPBringBackPutAway(nil);
            DPCallOriginal(DPAppDelegate_openURLs, self, app, @[ url ]);
        }, 40);
    }
}

void DPOpenLinkInLittleDia(NSURL *url) {
    DPOpenInLittleDia(url, DPNoteStackForLink(), ^{ NSBeep(); }, nil);
}

// Handed back to Dia as a link from Dia itself, which DPIsFromSelf leaves to open as a tab.
void DPOpenTabLinkInLittleDia(NSURL *url, NSWindow *source) {
    NSRect frame = DPOverWindowFrame(source);
    __weak NSWindow *over = source.visible ? source : nil;
    void (^asTab)(void) = ^{
        [NSWorkspace.sharedWorkspace openURLs:@[ url ] withApplicationAtURL:NSBundle.mainBundle.bundleURL
                                configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    };
    if (!DPOpenFramed(url, frame, DPNoteStackForLink(), asTab, ^(NSWindow *little) { DPPutLittleDiaOver(little, over); })) asTab();
}

void DPOpenBlankLittleDia(void) {
    DPOpenInLittleDia([NSURL URLWithString:@"about:blank"], DPNoteStackForLink(), ^{ NSBeep(); }, ^(NSWindow *window) { DPEditLittleDiaAddress(window); });
}

void DPInstallLittleDiaRoute(void) {
    DPHook(DPDiaOpenURLEvents, @selector(handleEvent:withReplyEvent:), (IMP)DPOpenURLEvents_handle);
    DPHook(DPDiaAppDelegate, @selector(application:openURLs:), (IMP)DPAppDelegate_openURLs);
}
