#import "StdPatch/StdPatch.h"
#import <objc/message.h>
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/AutoPip.h"
#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CompactCommandBar/CompactCommandBar.h"

extern DPPatch DPCommandBar, DPCommandBarBlur, DPCommandBarDarken, DPCommandBarShadow, DPCommandBarInteractive, DPCommandBarKeepText;
char DPOverlayKey;
static char DPLayoutKey, DPHomeKey, DPRecentKey, DPBlankKey, DPSplitKey, DPOwnBarKey, DPLeftTextKey, DPClosedAtKey, DPSeenKey;

static NSString *const DPHeightKey = @"commandBarHeight", *const DPDarknessKey = @"commandBarDarkness",
                *const DPBlurRadiusKey = @"commandBarBlurRadius", *const DPBlurWindowKey = @"commandBarBlurWindow",
                *const DPShadowIntensityKey = @"commandBarShadowIntensity";

@interface NSObject (DPCAFilter)
+ (id)filterWithType:(NSString *)type;
@end

NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static double DPTuned(NSString *key) {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{ DPHeightKey : @0.3, DPDarknessKey : @0.24, DPBlurRadiusKey : @4, DPBlurWindowKey : @NO,
                      DPShadowIntensityKey : @0.3 };
    });
    return [([DPSettings() objectForKey:key] ?: defaults[key]) doubleValue];
}

NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPMenuItemTitled(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

static const NSEventModifierFlags DPShortcutMods = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;
static const NSEventModifierFlags DPTriggerMods = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;

static BOOL DPMatchesShortcut(NSEvent *event, NSMenuItem *item) {
    return item.keyEquivalent.length && (event.modifierFlags & DPShortcutMods) == item.keyEquivalentModifierMask
        && [event.charactersIgnoringModifiers caseInsensitiveCompare:item.keyEquivalent] == NSOrderedSame;
}

static BOOL DPIsShortcut(NSEvent *event, NSString *menuTitle) {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp) return NO;
    return DPMatchesShortcut(event, DPMenuItemTitled(NSApp.mainMenu, menuTitle));
}

// Tabs already seen or kept on Dia's own page; a closed last tab's replacement is none of them.
static NSMutableSet<NSString *> *DPSeenTabs, *DPKeptTabs;

static NSString *DPNoteActiveTab(NSWindow *window, id scriptWindow, BOOL *seen) {
    NSString *active = DPActiveTabIDIn(scriptWindow);
    DPSeenTabs = DPSeenTabs ?: [NSMutableSet set];
    if (scriptWindow && !DPGet(window, &DPSeenKey)) {
        DPSet(window, &DPSeenKey, @YES);
        id tabs = DPValueForKey(scriptWindow, @"appleScriptTabs");
        if ([tabs isKindOfClass:NSArray.class])
            for (id tab in tabs) [DPSeenTabs addObject:DPTabID(tab) ?: @""];
    }
    if (seen) *seen = active && [DPSeenTabs containsObject:active];
    if (active) [DPSeenTabs addObject:active];
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (active && ![recent.lastObject isEqual:active]) DPSet(window, &DPRecentKey, recent.count ? @[ recent.lastObject, active ] : @[ active ]);
    return active;
}

static NSString *DPPreviousTabID(NSWindow *window) {
    NSArray *recent = DPGet(window, &DPRecentKey);
    return recent.count > 1 ? recent.firstObject : nil;
}

static NSMutableSet<NSString *> *DPWindowSet(NSWindow *window, const void *key) {
    NSMutableSet *set = DPGet(window, key);
    if (!set && window) DPSet(window, key, set = [NSMutableSet set]);
    return set;
}

NSMutableSet<NSString *> *DPBlanks(NSWindow *window) { return DPWindowSet(window, &DPBlankKey); }
NSMutableSet<NSString *> *DPSplits(NSWindow *window) { return DPWindowSet(window, &DPSplitKey); }

static BOOL DPInSplit(NSView *view) {
    NSView *pane = view;
    while (pane && !DPIsKind(pane, DPDiaSplitPane)) pane = pane.superview;
    for (NSView *other in pane.superview.subviews) if (other != pane && DPIsKind(other, DPDiaSplitPane)) return YES;
    return NO;
}

#pragma mark Overlay

NSTextView *DPBarText(DPCommandBarOverlay *overlay) {
    return (NSTextView *)DPFindView(overlay.panel, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
}

void DPFocusBar(DPCommandBarOverlay *overlay) {
    NSTextView *text = DPBarText(overlay);
    if (text && overlay.host.firstResponder != text) [overlay.host makeFirstResponder:text];
}

// Returning to the old tab stops Dia from closing ⌘L's bar on its own.
static void DPCloseCommandBarPopover(NSWindow *window) {
    NSView *popover = DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaPopover) && !DPIsFloatingChat(view); });
    NSView *text = DPFindView(popover, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    [(NSTextView *)text doCommandBySelector:@selector(cancelOperation:)];
}

static CGFloat DPSuggestionsHeight(NSView *panel) {
    CGFloat height = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarSuggestions); }).intrinsicContentSize.height;
    return height > 0 ? height + 8 : 0;
}

static NSView *DPCardIn(NSWindow *window) {
    NSView *pane = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane) && !view.isHiddenOrHasHiddenAncestor; });
    for (NSView *view = pane; view && view != window.contentView; view = view.superview)
        if (view.layer.cornerRadius > 0 && view.layer.maskedCorners && view.layer.masksToBounds) return view;
    return pane;
}

static NSRect DPBarFrame(NSView *view, NSSize size, CGFloat collapsedHeight) {
    NSString *position = DPChoice(&DPCommandBar);
    NSView *card = [position isEqual:@"page"] ? DPCardIn(view.window) : nil;
    if (NSIsEmptyRect(card.bounds)) card = nil;
    NSRect bounds = view.bounds, screen = view.window.screen.visibleFrame, page = card ? [view convertRect:card.bounds fromView:card] : bounds;
    NSPoint origin = NSMakePoint(NSMidX(page) - size.width / 2, NSMidY(page) - collapsedHeight / 2);
    if ([position isEqual:@"macos"] && view.window.screen) {
        NSPoint topLeft = NSMakePoint(NSMidX(screen) - size.width / 2, NSMaxY(screen) - (NSHeight(screen) - collapsedHeight) * DPTuned(DPHeightKey));
        origin = [view convertPoint:[view.window convertPointFromScreen:topLeft] fromView:nil];
    }
    NSRect inside = NSInsetRect(bounds, 12, 12);
    CGFloat x = MAX(MIN(origin.x, NSMaxX(inside) - size.width), NSMinX(inside));
    CGFloat y = MAX(MIN(origin.y, NSMaxY(inside) - size.height), NSMinY(inside));
    return NSMakeRect(round(x), round(y), size.width, size.height);
}

#pragma mark Shade

// CABackdropLayer is the only blur that reaches GPU-composited web content.
static CALayer *DPBlurLayer(void) {
    static Class backdropClass, filterClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        backdropClass = objc_getClass("CABackdropLayer");
        filterClass = objc_getClass("CAFilter");
    });
    CALayer *backdrop = [backdropClass new];
    id blur = [(id)filterClass filterWithType:@"gaussianBlur"];
    if (!backdrop || !blur) return nil;
    DPSetValueForKey(blur, @"inputRadius", @(DPTuned(DPBlurRadiusKey)));
    DPSetValueForKey(blur, @"inputNormalizeEdges", @YES);
    backdrop.filters = @[ blur ];
    return backdrop;
}

@interface DPPassThroughView : NSView
@end

@implementation DPPassThroughView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

static NSView *DPLayerView(NSRect frame, NSArray<CALayer *> *layers) {
    NSView *view = [[DPPassThroughView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.wantsLayer = YES;
    for (CALayer *layer in layers) {
        layer.frame = view.bounds;
        layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        [view.layer addSublayer:layer];
    }
    return view;
}

static void DPPlaceShade(NSView *shade, NSWindow *window) {
    NSView *card = DPCardIn(window);
    if (!shade || !card || shade.superview == card) return;
    shade.frame = card.bounds;
    [card addSubview:shade];
}

static NSView *DPAddWindowBlur(NSView *bar) {
    CALayer *blur = DPCommandBarBlur.on && DPTuned(DPBlurWindowKey) ? DPBlurLayer() : nil;
    if (!blur) return nil;
    NSView *view = DPLayerView(bar.superview.bounds, @[ blur ]);
    [bar.superview addSubview:view positioned:NSWindowBelow relativeTo:bar];
    return view;
}

static NSView *DPAddShade(NSWindow *window, BOOL blur) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray array];
    CALayer *backdrop = blur && DPCommandBarBlur.on ? DPBlurLayer() : nil;
    if (backdrop) [layers addObject:backdrop];
    if (DPCommandBarDarken.on) {
        CALayer *dim = [CALayer layer];
        dim.backgroundColor = [NSColor colorWithWhite:0 alpha:DPTuned(DPDarknessKey)].CGColor;
        [layers addObject:dim];
    }
    NSView *shade = DPLayerView(NSZeroRect, layers);
    DPPlaceShade(shade, window);
    return shade;
}

static void DPUpdatePanelShadow(NSView *panel) {
    if (!panel) return;
    if (DPCommandBarShadow.on) {
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:MIN(MAX(DPTuned(DPShadowIntensityKey), 0), 0.8)];
        shadow.shadowBlurRadius = 32;
        shadow.shadowOffset = NSMakeSize(0, 0);
        panel.shadow = shadow;
    } else {
        panel.shadow = nil;
    }
}

void DPShowShade(DPCommandBarOverlay *overlay) {
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
    DPUpdatePanelShadow(overlay.panel);
    NSString *returnID = DPTabID(overlay.returnTab);
    if (!returnID || [(NSSet *)DPGet(overlay.host, &DPBlankKey) containsObject:returnID]) return;
    overlay.windowBlur = DPAddWindowBlur(overlay.panel);
    overlay.shade = DPAddShade(overlay.host, !overlay.windowBlur);
}

@implementation DPCommandBarOverlay

- (void)dealloc {
    [_watch invalidate];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (BOOL)isFlipped { return YES; }

- (NSRect)frameForPanelSize:(NSSize)size {
    if (!DPIsKind(self.page, DPDiaPopover)) {
        // Measure the bar directly because tweaks may clip the panel and launch restore lays it out narrow first.
        NSView *bar = DPFindView(self.panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBar); });
        if (!self.collapsedHeight || NSWidth(bar.frame) != self.collapsedWidth) {
            self.collapsedWidth = NSWidth(bar.frame);
            self.collapsedHeight = NSHeight(bar.frame) - DPSuggestionsHeight(self.panel);
        }
        return DPBarFrame(self, size, self.collapsedHeight);
    }
    size.width = MIN(652, NSWidth((DPCardIn(self.host) ?: self).bounds) - 28);
    return DPBarFrame(self, size, size.height - DPSuggestionsHeight(self.panel));
}

- (void)layout {
    [super layout];
    if (self.panel) {
        NSRect target = [self frameForPanelSize:self.panel.frame.size];
        if (!NSEqualRects(self.panel.frame, target)) self.panel.frame = target;
    }
    DPPlaceShade(self.shade, self.host);
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.passingThrough) return nil;
    NSView *hit = [super hitTest:point];
    if (!hit || (self.panel && [hit isDescendantOf:self.panel])) return hit;
    return DPHiding() && DPInTabLayout([self viewUnder:point]) ? nil : self;
}

- (NSView *)viewUnder:(NSPoint)point {
    NSView *content = self.superview;
    self.passingThrough = YES;
    NSView *under = [content hitTest:[content convertPoint:point toView:content.superview]];
    self.passingThrough = NO;
    return under;
}

- (void)mouseDown:(NSEvent *)event { DPCancelCommandBar(self); }
- (void)rightMouseDown:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {
    if (!DPCommandBarInteractive.on) return;
    NSView *content = self.host.contentView;
    self.passingThrough = YES;
    NSView *under = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
    self.passingThrough = NO;
    [under scrollWheel:event];
}

@end

#pragma mark Presenting

static void DPHideBars(NSView *page, BOOL hidden) {
    NSView *pane = page.superview;
    while (pane && !DPIsKind(pane, DPDiaContentPane)) pane = pane.superview;
    for (NSView *bar in pane.subviews) {
        if (!DPIsKind(bar, DPDiaToolbar) && !DPIsKind(bar, DPDiaBookmarksBar)) continue;
        if (hidden && !bar.hidden) DPSet(bar, &DPBlankKey, @YES);
        else if (hidden || !DPGet(bar, &DPBlankKey)) continue;
        else DPSet(bar, &DPBlankKey, nil);
        bar.hidden = hidden;
    }
}

void DPShowHiddenBars(void) {
    Class pageCls = objc_getClass(DPDiaNewTabPage);
    if (!pageCls) return;
    for (NSWindow *window in NSApp.windows)
        DPFindView(window.contentView, ^BOOL(NSView *page) {
            if ([page isKindOfClass:pageCls]) DPHideBars(page, NO);
            return NO;
        });
}

static void DPHidePage(NSView *page, BOOL hidden) {
    page.hidden = hidden;
    if (!hidden) DPHideBars(page, NO);
    for (NSView *view = page.superview; view; view = view.superview)
        if (DPIsKind(view, DPDiaContentPane)) view.needsLayout = YES;
}

BOOL DPHasStrip(NSWindow *window) {
    return DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabStripTabs) && !view.isHiddenOrHasHiddenAncestor; }) != nil;
}

static BOOL DPHasURL(id tab);

void DPMakeBlank(NSView *page, NSString *tab, NSString *closing) {
    if (!tab || DPInSplit(page)) return;
    [DPBlanks(page.window) addObject:tab];
    DPSet(page, &DPBlankKey, @YES);
    DPHidePage(page, YES);
    if (DPHasStrip(page.window) || !DPOnlyListedTab(tab, closing, page.window) || DPHasURL(DPScriptTab(page.window, tab))) return;
    DPHideBlank(tab, YES, page.window);
    if (DPHidesTab(tab)) DPHideBars(page, YES);
}

NSView *DPBlankPage(NSWindow *window) {
    return DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNewTabPage) && DPGet(view, &DPBlankKey); });
}

id DPDismiss(DPCommandBarOverlay *overlay, BOOL closing) {
    [overlay.watch invalidate];
    overlay.watch = nil;
    DPShowTabRow(DPTabID(overlay.openedTab), closing);
    if (overlay.keyMonitor) [NSEvent removeMonitor:overlay.keyMonitor];
    overlay.keyMonitor = nil;
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
    if (!overlay.host) return nil;
    if (overlay.openedTab) DPStandInForTab(overlay.host, DPTabID(overlay.openedTab));
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
    overlay.host = nil;
    NSView *page = overlay.page, *panel = overlay.panel, *home = DPGet(panel, &DPHomeKey);
    DPSet(page, &DPOverlayKey, nil);
    DPSet(panel, &DPHomeKey, nil);
    panel.shadow = nil;
    if (panel && home) [home addSubview:panel];
    for (NSView *view in overlay.shownShadows) view.hidden = YES;
    DPHidePage(page, NO);
    home.needsLayout = YES;
    [overlay removeFromSuperview];
    return overlay.openedTab;
}

static BOOL DPNowhereToGo(DPCommandBarOverlay *overlay) {
    NSWindow *host = overlay.host;
    id scriptWindow = overlay.returnTab ? DPScriptWindow(host) : nil;
    // Once another space is in front, the bar's tab and the tab it came from are counted in their own space.
    NSString *openedID = DPTabID(overlay.openedTab);
    id space = DPScriptTabIn(scriptWindow, openedID) ? scriptWindow : DPScriptProfileHolding(scriptWindow, openedID) ?: scriptWindow;
    id tabs = DPValueForKey(space, @"appleScriptTabs");
    NSUInteger count = [tabs isKindOfClass:NSArray.class] ? [tabs count] : 0;
    return !overlay.returnTab || (!DPScriptTabIn(space, DPTabID(overlay.returnTab)) && count < 2);
}

static id DPDismissCommandBar(DPCommandBarOverlay *overlay) { return DPDismiss(overlay, NO); }

void DPCancelCommandBar(DPCommandBarOverlay *overlay) {
    if (DPParkSpare(overlay)) return;
    NSView *page = overlay.page;
    BOOL overBlank = overlay.overBlank;
    if (DPIsKind(page, DPDiaPopover)) [DPBarText(overlay) doCommandBySelector:@selector(cancelOperation:)];
    else if (DPCommandBarKeepText.on) DPSet(overlay.host, &DPLeftTextKey, DPBarText(overlay).string.copy);
    BOOL nowhereToGo = DPNowhereToGo(overlay);
    id tab = DPDismiss(overlay, !overBlank && !nowhereToGo);
    if (!tab) return;
    DPNoteSpare(DPTabID(tab), NO);
    // Closing a window's only tab would close the window, and Dia with it.
    if (overBlank || nowhereToGo) DPMakeBlank(page, DPTabID(tab), nil);
    else DPCloseTab(tab);
}

static void DPCloseOnNewLayout(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    NSNumber *strip = DPGet(overlay, &DPLayoutKey);
    if (overlay.openedTab && DPHidesTab(DPTabID(overlay.openedTab))) {
        if (!strip) DPSet(overlay, &DPLayoutKey, @(DPHasStrip(window)));
        else if (strip.boolValue != DPHasStrip(window)) DPCancelCommandBar(overlay);
    }
    if (DPSpareIn(window) && DPHasStrip(window)) DPDropSpare(window);
}

// A result is opening in the bar's tab. A chat loads no page; Dia empties the bar once it has taken what was typed.
static BOOL DPTaken(DPCommandBarOverlay *overlay, id tab) {
    NSString *url = DPValueForKey(tab, @"URL");
    return (overlay.picked && !DPBarText(overlay).string.length) || !(url == overlay.startURL || [url isEqual:overlay.startURL]);
}

// Midway through a swipe between spaces Dia lists no tabs at all. Wait it out, but not for good.
static BOOL DPSwipeSettling(DPCommandBarOverlay *overlay, id scriptWindow) {
    id tabs = DPValueForKey(scriptWindow, @"appleScriptTabs");
    if (![tabs isKindOfClass:NSArray.class] || [tabs count]) return overlay.listlessSince = 0, NO;
    CFTimeInterval now = CACurrentMediaTime();
    if (!overlay.listlessSince) overlay.listlessSince = now;
    return now - overlay.listlessSince < 3;
}

// Another space came forward, leaving the bar's tab in the old one. Close it unless a result is opening in it, it
// was opened over a blank tab, or it's its space's only tab, since closing that would empty the space.
static void DPLeaveSpace(DPCommandBarOverlay *overlay, id scriptWindow) {
    NSString *openedID = DPTabID(overlay.openedTab);
    id space = DPScriptProfileHolding(scriptWindow, openedID), left = DPScriptTabIn(space, openedID), spaceTabs = DPValueForKey(space, @"appleScriptTabs");
    BOOL close = left && DPHiding() && !overlay.overBlank && !overlay.picked && !DPTaken(overlay, left)
              && [spaceTabs isKindOfClass:NSArray.class] && [spaceTabs count] > 1;
    DPDismiss(overlay, close);
    DPNoteSpare(openedID, NO);
    if (close) DPCloseTab(left);
}

static void DPWatchNewTab(DPCommandBarOverlay *overlay, id scriptWindow) {
    NSWindow *window = overlay.host;
    NSView *content = window.contentView;
    if (!window) return (void)DPDismissCommandBar(overlay);
    if (DPSpareIn(window) == overlay) return;
    if (overlay.superview != content) {
        overlay.frame = content.bounds;
        [content addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    }
    DPPlaceShade(overlay.shade, window);
    scriptWindow = scriptWindow ?: DPScriptWindow(window);
    id tab = DPScriptTabIn(scriptWindow, DPTabID(overlay.openedTab));
    if (!tab && DPSwipeSettling(overlay, scriptWindow)) return;
    if (!tab) return DPLeaveSpace(overlay, scriptWindow);
    overlay.listlessSince = 0;
    NSString *active = DPActiveTabIDIn(scriptWindow);
    if (active && ![active isEqual:DPTabID(tab)] && ![active isEqual:DPTabID(overlay.returnTab)]) {
        NSString *left = DPTabID(overlay.returnTab);
        if (DPParkSpare(overlay)) return DPStandInWhileSwitching(window, DPTabID(tab), left);
        DPDismiss(overlay, YES);
        DPStandInWhileSwitching(window, DPTabID(tab), left);
        return DPCloseTab(tab);
    }
    if (overlay.returnTab && !DPScriptTabIn(scriptWindow, DPTabID(overlay.returnTab))) {
        DPDismissCommandBar(overlay);
        return DPFocusTab(tab);
    }
    if (!DPTaken(overlay, tab)) return;
    DPDismissCommandBar(overlay);
    DPNoteSpare(DPTabID(tab), NO);
    DPFocusTab(tab);
}

static void DPWatchSoon(DPCommandBarOverlay *overlay, int checks) {
    if (!checks || !overlay.host) return;
    __weak DPCommandBarOverlay *weak = overlay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weak.host) return;
        DPWatchNewTab(weak, nil);
        DPWatchSoon(weak, checks - 1);
    });
}

static BOOL DPClickSubmits(DPCommandBarOverlay *overlay, NSEvent *event) {
    NSView *hit = [overlay hitTest:[overlay.superview convertPoint:event.locationInWindow fromView:nil]];
    NSView *suggestions = DPCommandBarPart(overlay.panel, DPDiaCommandBarSuggestions), *go = DPGoButton(DPCommandBarPart(overlay.panel, DPDiaCommandBarToolbar));
    return (suggestions && [hit isDescendantOf:suggestions]) || (go && [hit isDescendantOf:go]);
}

id DPWatchKeys(DPCommandBarOverlay *overlay) {
    __weak DPCommandBarOverlay *weak = overlay;
    NSEventMask mask = NSEventMaskKeyDown | NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown;
    return [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        DPCommandBarOverlay *overlay = weak;
        if (!overlay || event.window != overlay.host || overlay.host.attachedSheet) return event;
        if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown) return DPHiding() ? DPTabLayoutMouseDown(overlay, event) : event;
        BOOL click = event.type == NSEventTypeLeftMouseUp;
        if (click) DPTabLayoutMouseUp(overlay);
        if (click || event.keyCode == 36 || event.keyCode == 76) {
            BOOL submits = click ? DPClickSubmits(overlay, event) : !DPBarText(overlay).hasMarkedText;
            overlay.picked = overlay.picked || (submits && DPBarText(overlay).string.length > 0);
            if (overlay.openedTab) DPWatchSoon(overlay, 60);
            return event;
        }
        BOOL escape = event.keyCode == 53, close = NO;
        if (!escape && (event.modifierFlags & DPTriggerMods)) {
            NSMenuItem *closeItem = DPMenuItemTitled(NSApp.mainMenu, @"Close Tab");
            close = closeItem ? DPMatchesShortcut(event, closeItem)
                              : (event.modifierFlags & DPShortcutMods) == NSEventModifierFlagCommand && event.keyCode == 13;
        }
        if (!escape && !close) return event;
        if (escape) {
            if (DPBarText(overlay).hasMarkedText) return event;
            NSRect bar = [overlay.host convertRectToScreen:[overlay.panel convertRect:overlay.panel.bounds toView:nil]];
            for (NSWindow *child in overlay.host.childWindows)
                if (child.visible && NSIntersectsRect(child.frame, bar)) return event;
        }
        DPCancelCommandBar(overlay);
        return nil;
    }];
}

// Dia detaches the previous web view mid-switch and retitles the window; restore both.
static void DPGoBack(DPCommandBarOverlay *overlay) {
    NSView *web = DPFindView(overlay.host.contentView, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView") && !view.isHiddenOrHasHiddenAncestor; });
    NSView *paneHost = web.superview;
    NSString *returnID = DPTabID(overlay.returnTab);
    __weak DPCommandBarOverlay *weak = overlay;
    DPFocusTab(overlay.returnTab);
    if (web) {
        CFRunLoopObserverRef beforeDraw = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, NO, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            if (web.superview || !paneHost.window) return;
            [paneHost addSubview:web positioned:NSWindowBelow relativeTo:nil];
            [NSLayoutConstraint activateConstraints:@[
                [web.topAnchor constraintEqualToAnchor:paneHost.topAnchor], [web.bottomAnchor constraintEqualToAnchor:paneHost.bottomAnchor],
                [web.leadingAnchor constraintEqualToAnchor:paneHost.leadingAnchor], [web.trailingAnchor constraintEqualToAnchor:paneHost.trailingAnchor],
            ]];
            NSWindow *window = paneHost.window;
            NSResponder *focus = window.firstResponder;
            if (weak.superview || (focus != paneHost && focus != window) || ![DPActiveTabID(window) isEqual:returnID]) return;
            NSView *page = DPFindView(web, ^BOOL(NSView *view) { return DPIsKind(view, "RenderWidgetHostViewCocoa"); });
            if (page) [window makeFirstResponder:page];
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), beforeDraw, kCFRunLoopCommonModes);
        CFRelease(beforeDraw);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview && !weak.hidden) DPFocusBar(weak); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        // Refocusing an already-active tab steals focus from the bar.
        if (!weak.superview || [DPActiveTabID(weak.host) isEqual:DPTabID(weak.returnTab)]) return;
        DPFocusTab(weak.returnTab);
        dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview && !weak.hidden) DPFocusBar(weak); });
    });
}

// Match the new-tab bar's 21pt top inset and 16pt font when Dia resets ⌘L's 19pt inset.
static CGFloat DPStyleAsNewTab(NSView *panel) {
    NSView *bar = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBar); });
    NSView *input = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarText); });
    NSTextView *text = (NSTextView *)DPFindView(input, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    __strong NSFont **font = (__strong NSFont **)DPIvar(input, "font");
    double *top = DPIvar(bar, "layoutConfiguration");
    if (!text || !font || !top) return 0;
    if (text.font.pointSize != 16) *font = text.font = [NSFont systemFontOfSize:16];
    CGFloat grown = 21 - *top;
    *top = 21;
    bar.needsLayout = YES;
    [bar layoutSubtreeIfNeeded];
    [text scrollRangeToVisible:text.selectedRange];
    return grown;
}

static DPCommandBarOverlay *DPLiftBar(NSView *page, id tabBehind) {
    NSWindow *window = page.window;
    NSView *content = window.contentView, *panel = DPFindView(page, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaAssistantPanel); });
    if (!DPCommandBar.on || !panel || !content || DPGet(page, &DPOverlayKey)) return nil;
    DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:content.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlay.page = page;
    overlay.panel = panel;
    overlay.host = window;
    overlay.returnTab = tabBehind;
    [content addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    DPSet(page, &DPOverlayKey, overlay);
    DPSet(window, &DPOverlayKey, overlay);
    DPSet(panel, &DPHomeKey, panel.superview);
    [overlay addSubview:panel];
    NSMutableArray<NSView *> *shadows = [NSMutableArray array];
    for (NSView *view in panel.subviews)
        if (DPIsKind(view, DPDiaShadowView) && view.hidden) {
            view.hidden = NO;
            [shadows addObject:view];
        }
    overlay.shownShadows = shadows;
    DPShowShade(overlay);
    panel.frame = [overlay frameForPanelSize:panel.frame.size];
    DPHidePage(page, YES);
    DPFocusBar(overlay);
    overlay.keyMonitor = DPWatchKeys(overlay);
    return overlay;
}

static BOOL DPHasURL(id tab) { return [[DPValueForKey(tab, @"URL") description] length] > 0; }

static void DPCaughtUpSoon(NSWindow *window) {
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPDiaCaughtUp(weak); });
}

static void DPPresentCommandBar(NSView *page, BOOL overBlank) {
    NSWindow *window = page.window;
    DPCaughtUpSoon(window);
    DPCloseCommandBarPopover(window);
    id scriptWindow = DPScriptWindow(window), openedTab = DPValueForKey(scriptWindow, @"activeTab");
    NSString *openedID = DPTabID(openedTab), *returnID = DPPreviousTabID(window);
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (![recent.lastObject isEqual:openedID]) returnID = recent.lastObject;
    id returnTab = overBlank || !returnID ? nil : DPScriptTabIn(scriptWindow, returnID);
    DPKeptTabs = DPKeptTabs ?: [NSMutableSet set];
    BOOL hasPage = openedID && !overBlank && (DPHasURL(openedTab) || [DPKeptTabs containsObject:openedID]);
    BOOL returnsToPage = returnTab && [DPKeptTabs containsObject:returnID] && !DPHasURL(returnTab);
    // Keep Dia's own page for tabs with history or splits, since returning mid-switch to a split crashes Dia.
    if (hasPage || returnsToPage || DPInSplit(page) || (!overBlank && [(NSSet *)DPGet(window, &DPSplitKey) containsObject:returnID])) {
        if (openedID) [DPKeptTabs addObject:openedID];
        DPStopExpecting();
        return (void)DPSet(page, &DPOwnBarKey, @YES);
    }
    DPCommandBarOverlay *overlay = openedTab ? DPLiftBar(page, returnTab) : nil;
    if (!overlay) return DPStopExpecting();
    if (overBlank) {
        [DPBlanks(window) removeObject:openedID];
        DPSet(page, &DPBlankKey, nil);
    }
    NSTextView *text = DPBarText(overlay);
    NSString *left = DPCommandBarKeepText.on ? DPGet(window, &DPLeftTextKey) : nil;
    DPSet(window, &DPLeftTextKey, nil);
    if (overBlank || left.length) [text insertText:left ?: @"" replacementRange:NSMakeRange(0, text.string.length)];
    if (left.length) [text selectAll:nil];
    overlay.overBlank = overBlank;
    overlay.openedTab = openedTab;
    overlay.startURL = DPValueForKey(openedTab, @"URL");
    DPSet(overlay, &DPLayoutKey, @(DPHasStrip(window)));
    if (overlay.returnTab) {
        DPHideTabRow(openedID, window);
        DPStandInFor(window, openedID);
        DPNoteSpare(openedID, YES);
    } else if (overBlank && DPParksTab(openedID)) {
        DPFreezeLists(window);
        DPParkTab(openedID, NO);
        DPStandInFor(window, openedID);
    } else DPStopExpecting();

    DPWatch(overlay);
    if (!overlay.returnTab) return DPParkIfSpare(overlay);
    __weak DPCommandBarOverlay *weak = overlay;
    // Defer DPGoBack past Dia's tab switch (calling it inline crashes) inside a transaction to hide the flash.
    [CATransaction begin];
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        @try { if (weak.superview) { DPGoBack(weak); DPParkIfSpare(weak); } } @finally { [CATransaction commit]; }
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

void DPWatch(DPCommandBarOverlay *overlay) {
    __weak DPCommandBarOverlay *weak = overlay;
    [overlay.watch invalidate];
    overlay.watch = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (weak) DPWatchNewTab(weak, nil); else [timer invalidate];
    }];
}

static BOOL DPOpenOverBlank(NSWindow *window) {
    NSSet *blanks = DPGet(window, &DPBlankKey);
    if (!DPCommandBar.on || !blanks.count || ![blanks containsObject:DPActiveTabID(window)]) return NO;
    NSView *page = DPBlankPage(window);
    if (page) DPPresentCommandBar(page, YES);
    return page != nil;
}

static void DPCloseLeftBlank(NSWindow *window) {
    NSMutableSet<NSString *> *blanks = DPGet(window, &DPBlankKey);
    if (!window || !blanks.count || DPGet(window, &DPOverlayKey)) return;
    NSString *previous = DPPreviousTabID(window), *latest = [DPGet(window, &DPRecentKey) lastObject];
    id scriptWindow = [blanks containsObject:previous] && ![blanks containsObject:latest] ? DPScriptWindow(window) : nil;
    id blank = DPScriptTabIn(scriptWindow, previous);
    if (!blank || !DPScriptTabIn(scriptWindow, latest)) return;
    [blanks removeObject:previous];
    DPShowTabRow(previous, YES);
    if (!DPHasURL(blank)) DPCloseTab(blank);
}

#pragma mark Hooks

static void DPPanel_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if ([self.superview isKindOfClass:DPCommandBarOverlay.class]) {
        DPCommandBarOverlay *overlay = (DPCommandBarOverlay *)self.superview;
        if (DPIsKind(overlay.page, DPDiaPopover)) {
            frame.size.height += DPStyleAsNewTab(self);
            overlay.sizedAt = CACurrentMediaTime();
        }
        frame = [overlay frameForPanelSize:frame.size];
    }
    DPCallOriginal(DPPanel_setFrame, self, frame);
}

static DPCommandBarOverlay *DPOverlayAbove(NSView *view) {
    while (view && ![view isKindOfClass:DPCommandBarOverlay.class]) view = view.superview;
    return (DPCommandBarOverlay *)view;
}

static void DPSuggestions_invalidateIntrinsicContentSize(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSuggestions_invalidateIntrinsicContentSize, self);
    if (!DPCommandBar.on) return;
    DPCommandBarOverlay *overlay = DPOverlayAbove(self);
    if (!overlay || DPIsKind(overlay.page, DPDiaPopover)) return;
    __weak NSView *suggestions = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *panel = overlay.panel;
        CGFloat want = overlay.collapsedHeight + DPSuggestionsHeight(panel);
        if (!panel || suggestions.intrinsicContentSize.height < 0 || NSHeight(panel.frame) == want) return;
        panel.frame = [overlay frameForPanelSize:NSMakeSize(NSWidth(panel.frame), want)];
        for (NSView *view = suggestions.superview; view && view != panel; view = view.superview) {
            view.frame = NSMakeRect(0, 0, NSWidth(view.frame), NSHeight(panel.frame));
            view.needsLayout = YES;
        }
        [panel layoutSubtreeIfNeeded];
    });
}

static void DPCapability_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPCommandBar.on) return DPCallOriginal(DPCapability_mouseDown, self, event);
    DPCommandBarOverlay *overlay = DPOverlayAbove(self);
    if (!overlay.returnTab) return DPCallOriginal(DPCapability_mouseDown, self, event);
    DPFocusBar(overlay);
    [DPBarText(overlay) insertText:@"@" replacementRange:DPBarText(overlay).selectedRange];
}

static BOOL DPCloseStoodIn(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (!DPHidesTab(DPTabID(overlay.openedTab))) return NO;
    if (!(NSEvent.pressedMouseButtons & 1)) return DPCancelCommandBar(overlay), YES;
    __weak DPCommandBarOverlay *weak = overlay;
    __block id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:^NSEvent *(NSEvent *event) {
        if (monitor) [NSEvent removeMonitor:monitor];
        monitor = nil;
        if (weak.host) DPCancelCommandBar(weak);
        return event;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!monitor) return;
        [NSEvent removeMonitor:monitor];
        monitor = nil;
    });
    return YES;
}

static BOOL DPClickedNewTab(NSWindow *window) {
    if (!DPCommandBar.on) return NO;
    if (DPCloseStoodIn(window)) return YES;
    DPSet(window, &DPClosedAtKey, nil);
    DPNotMakingSpare();
    if (DPShowSpare(window) || DPOpenOverBlank(window)) return YES;
    DPExpectNewTab(window);
    return NO;
}

static void DPNewTabButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (DPClickedNewTab(self.window)) return;
    DPHoldAutoPip();
    DPCallOriginal(DPNewTabButton_mouseDown, self, event);
}

static void DPPlusButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPHiding() || !DPIsKind(self.superview, DPDiaTabStripTabs) || !DPClickedNewTab(self.window)) DPCallOriginal(DPPlusButton_mouseDown, self, event);
}

static BOOL DPOverPinnedHeader(NSView *tabList, id gesture) {
    Class headerCls = NSClassFromString(@"DPPinnedHeader");
    if (!headerCls || ![gesture respondsToSelector:@selector(locationInView:)]) return NO;
    NSView *header = DPFindView(tabList, ^BOOL(NSView *view) { return [view isKindOfClass:headerCls]; });
    if (!header || header.isHiddenOrHasHiddenAncestor || !header.superview) return NO;
    return NSPointInRect([gesture locationInView:header.superview], header.frame);
}

static void DPTabList_backgroundDoubleClick(NSView *self, SEL _cmd, id gesture) {
    if (DPOverPinnedHeader(self, gesture) || !DPHiding() || !DPClickedNewTab(self.window))
        DPCallOriginal(DPTabList_backgroundDoubleClick, self, gesture);
}

static BOOL DPToolbarShowing(NSWindow *window);

static BOOL DPResponderInSidePanel(id responder) {
    if (![responder isKindOfClass:NSView.class]) return NO;
    for (NSView *view = responder; view; view = view.superview) {
        if (DPIsKind(view, DPDiaAssistantPanel) || DPIsKind(view, DPDiaChatHeader)) return YES;
        if (DPIsKind(view, DPDiaPopover) && DPIsFloatingChat(view)) return YES;
        if ([NSStringFromClass(view.class) containsString:@"ExtensionSidePanel"]) return YES;
    }
    return NO;
}

static NSView *DPVisiblePeek(NSWindow *window) {
    Class card = NSClassFromString(@"DPPeekCard");
    return card ? DPFindView(window.contentView, ^BOOL(NSView *view) { return [view isKindOfClass:card] && !view.isHiddenOrHasHiddenAncestor; }) : nil;
}

// Typing belongs to another field when text outside the blank tab, or a Side Chat or Peek page, has the keyboard.
static BOOL DPTypingElsewhere(NSWindow *window) {
    NSResponder *responder = window.firstResponder;
    if (![responder isKindOfClass:NSView.class]) return NO;
    NSView *view = (NSView *)responder, *blank = DPBlankPage(window);
    if (blank && [view isDescendantOf:blank]) return NO;
    if ([view isKindOfClass:NSText.class] || DPResponderInSidePanel(view)) return YES;
    NSView *peek = DPVisiblePeek(window);
    return peek && [view isDescendantOf:peek];
}

static BOOL DPVisiblePeekTakesCommandL(NSWindow *window) {
    if (DPResponderInSidePanel(window.firstResponder)) return NO;
    NSView *peek = DPVisiblePeek(window);
    if (!peek) return NO;
    SEL closingSel = NSSelectorFromString(@"closing"), toolbarSel = NSSelectorFromString(@"toolbar");
    if ([peek respondsToSelector:closingSel] && ((BOOL (*)(id, SEL))objc_msgSend)(peek, closingSel)) return NO;
    return [peek respondsToSelector:toolbarSel] && ((id (*)(id, SEL))objc_msgSend)(peek, toolbarSel) != nil;
}

static NSEvent *DPCommandBarKey(NSEvent *event) {
    NSWindow *window = event.window;
    if (!DPCommandBar.on || !DPIsKind(window, DPDiaWindow) || window.attachedSheet) return event;
    NSEventModifierFlags mods = event.modifierFlags;
    BOOL hasShortcutMod = (mods & DPTriggerMods) != 0;
    if (hasShortcutMod && DPIsShortcut(event, @"Close Tab")) DPSet(window, &DPClosedAtKey, @(event.timestamp));
    NSSet *blanks = DPGet(window, &DPBlankKey);
    if (blanks.count && DPHiding() && !(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl))
        && !DPGet(window, &DPOverlayKey) && event.characters.length) {
        unichar ch = [event.characters characterAtIndex:0];
        if (ch >= 0x20 && ch != 0x7f && [blanks containsObject:DPActiveTabID(window)] && !DPTypingElsewhere(window)) {
            DPOpenOverBlank(window);
            return event;
        }
    }
    if (!hasShortcutMod) return event;
    BOOL newTab = DPIsShortcut(event, @"New Tab");
    if (!(newTab || DPIsShortcut(event, @"Open Command Bar"))) return event;
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (!newTab && !overlay && DPVisiblePeekTakesCommandL(window)) return event;
    DPSet(window, &DPClosedAtKey, nil);
    DPNotMakingSpare();
    if (event.isARepeat) {
        if (overlay) DPFocusBar(overlay);
        return nil;
    }
    if (DPWaitForDia(window, event, newTab)) return nil;
    if (newTab && DPIsKind(overlay.page, DPDiaPopover) && !DPSpareIn(window)) {
        DPExpectNewTab(window);
        return DPHandToDia(window, event, newTab);
    }
    if (overlay && !newTab && overlay.openedTab) {
        DPHandOver(overlay);
        return DPToolbarShowing(window) ? event : DPHandToDia(window, event, newTab);
    }
    if (overlay) {
        DPCancelCommandBar(overlay);
        if (newTab == (overlay.openedTab != nil)) return nil;
    }
    if ((newTab && DPShowSpare(window)) || DPOpenOverBlank(window)) return nil;
    if (newTab) DPExpectNewTab(window);
    return newTab || !DPToolbarShowing(window) ? DPHandToDia(window, event, newTab) : event;
}

static BOOL DPToolbarShowing(NSWindow *window) {
    return DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaToolbar) && !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0;
    }) != nil;
}

static void DPRemoveAnimations(CALayer *layer) {
    [layer removeAllAnimations];
    for (CALayer *sublayer in layer.sublayers) DPRemoveAnimations(sublayer);
}

static void DPShowWhenBuilt(DPCommandBarOverlay *overlay) {
    overlay.alphaValue = overlay.shade.alphaValue = 0;
    CFTimeInterval opened = CACurrentMediaTime();
    __weak DPCommandBarOverlay *weak = overlay;
    NSTimer *check = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        DPCommandBarOverlay *overlay = weak;
        if (!overlay.host || !DPCommandBar.on) return [timer invalidate];
        NSView *toolbar = DPFindView(overlay.panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarToolbar); });
        CFTimeInterval now = CACurrentMediaTime();
        if (!(toolbar.alphaValue == 1 && now - overlay.sizedAt > 0.02) && now - opened < 0.5) return;
        [timer invalidate];
        DPRemoveAnimations(overlay.panel.layer);
        overlay.alphaValue = overlay.shade.alphaValue = 1;
        DPFinishHandOver(overlay.host);
        DPDiaCaughtUp(overlay.host);
    }];
    [NSRunLoop.mainRunLoop addTimer:check forMode:NSRunLoopCommonModes];
}

// Route clicks inside the lifted bar back to the hidden popover so Dia doesn't dismiss ⌘L.
static NSView *DPPopover_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    if (DPCommandBar.on) {
        DPCommandBarOverlay *overlay = DPGet(self, &DPOverlayKey);
        if (overlay.panel && !overlay.passingThrough) {
            NSRect bar = [self.superview convertRect:overlay.panel.bounds fromView:overlay.panel];
            if (NSPointInRect(point, bar)) return self;
        }
    }
    return DPCallOriginal(DPPopover_hitTest, self, point);
}

static void DPPopover_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopover_viewDidMoveToWindow, self);
    DPCommandBarOverlay *overlay = DPGet(self, &DPOverlayKey);
    if (overlay) return (void)DPDismissCommandBar(overlay);
    if (!DPCommandBar.on || !self.window || DPToolbarShowing(self.window) || DPIsFloatingChat(self)) return;
    overlay = DPLiftBar(self, DPValueForKey(DPScriptWindow(self.window), @"activeTab"));
    if (overlay) DPShowWhenBuilt(overlay);
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    __weak NSWindow *window = self.window;
    if (!window) return;
    id scriptWindow = DPScriptWindow(window);
    NSString *active = DPNoteActiveTab(window, scriptWindow, NULL);
    if (active && DPInSplit(self)) [DPSplits(window) addObject:active];
    else if (active) [(NSMutableSet *)DPGet(window, &DPSplitKey) removeObject:active];
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay.openedTab) DPWatchNewTab(overlay, scriptWindow);
    if ([(NSSet *)DPGet(window, &DPBlankKey) count])
        dispatch_async(dispatch_get_main_queue(), ^{ DPCloseLeftBlank(window); });
}

static void DPScheduleLayoutCheck(NSWindow *window) {
    if (!DPCommandBar.on || (!DPGet(window, &DPOverlayKey) && !DPSpareIn(window))) return;
    __weak NSWindow *weak = window;
    dispatch_async(dispatch_get_main_queue(), ^{ DPCloseOnNewLayout(weak); });
}

static void DPTabList_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabList_viewDidMoveToWindow, self);
    DPScheduleLayoutCheck(self.window);
}

static void DPStrip_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPStrip_viewDidMoveToWindow, self);
    DPScheduleLayoutCheck(self.window);
}

static void DPNewTabPage_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNewTabPage_viewDidMoveToWindow, self);
    NSWindow *window = self.window;
    if (!window) return;
    id scriptWindow = DPScriptWindow(window);
    BOOL seen;
    NSString *active = DPNoteActiveTab(window, scriptWindow, &seen);
    if (!DPCommandBar.on || DPAdoptSpare(window, self)) return;
    NSString *previous = DPPreviousTabID(window);
    NSMutableSet<NSString *> *blanks = DPGet(window, &DPBlankKey);
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay && [active isEqual:DPTabID(overlay.openedTab)]) {
        if (overlay.returnTab) dispatch_async(dispatch_get_main_queue(), ^{ if (overlay.host) DPFocusTab(overlay.returnTab); });
        return;
    }
    // Dia opens a closing last tab's replacement before removing it; returning to a closing tab crashes Dia.
    NSNumber *closedAt = DPGet(window, &DPClosedAtKey);
    DPSet(window, &DPClosedAtKey, nil);
    BOOL justClosed = closedAt && NSProcessInfo.processInfo.systemUptime - closedAt.doubleValue < 1;
    BOOL closing = justClosed || DPIsShortcut(NSApp.currentEvent, @"Close Tab") || (previous && !DPScriptTabIn(scriptWindow, previous));
    BOOL wasBlank = [blanks containsObject:active];
    if (active && (wasBlank || closing)) {
        if (!wasBlank && (seen || DPInSplit(self))) {
            [DPKeptTabs addObject:active];
            DPSet(self, &DPOwnBarKey, @YES);
        } else DPMakeBlank(self, active, previous);
        if (overlay.returnTab && !DPScriptTabIn(scriptWindow, DPTabID(overlay.returnTab))) DPCancelCommandBar(overlay);
        return;
    }
    if (overlay) DPCancelCommandBar(overlay);
    id blank = [blanks containsObject:previous] ? DPScriptTabIn(scriptWindow, previous) : nil;
    if (blank) {
        [blanks removeObject:previous];
        DPShowTabRow(previous, YES);
        if (DPHasURL(blank)) blank = nil;
        else DPCloseTab(blank);
    }
    NSView *pane = self.superview;
    while (pane && !DPIsKind(pane, DPDiaContentPane)) pane = pane.superview;
    [pane layoutSubtreeIfNeeded];
    DPPresentCommandBar(self, blank != nil);
}

static void DPApplyCommandBar(DPPatch *patch) {
    BOOL on = DPCommandBar.on;
    for (NSWindow *window in NSApp.windows) {
        if (!on) {
            for (NSString *blank in (NSSet *)DPGet(window, &DPBlankKey)) DPHideBlank(blank, NO, window);
            DPSet(window, &DPBlankKey, nil);
            DPDropSpare(window);
            DPClearCatchUp(window);
            DPFinishHandOver(window);
        }
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (!overlay) continue;
        if (on) {
            DPShowShade(overlay);
            overlay.needsLayout = YES;
            continue;
        }
        BOOL nowhereToGo = DPNowhereToGo(overlay);
        id tab = DPDismissCommandBar(overlay);
        DPNoteSpare(DPTabID(tab), NO);
        if (tab && !nowhereToGo) DPCloseTab(tab);
    }
    if (!on) {
        DPCleanHideTab();
        DPUpdateSpareTimer();
        Class pageCls = objc_getClass(DPDiaNewTabPage);
        if (pageCls)
            for (NSWindow *window in NSApp.windows)
                DPFindView(window.contentView, ^BOOL(NSView *page) {
                    if ([page isKindOfClass:pageCls] && DPGet(page, &DPBlankKey)) {
                        DPSet(page, &DPBlankKey, nil);
                        DPHidePage(page, NO);
                    }
                    return NO;
                });
        return;
    }
    if (patch != &DPCommandBar) return;
    for (NSView *page in DPFindViews(DPDiaNewTabPage))
        if (!DPGet(page, &DPBlankKey) && !DPGet(page, &DPOverlayKey) && !DPGet(page, &DPOwnBarKey)) DPPresentCommandBar(page, NO);
}

static NSString *DPVerifyCommandBar(DPPatch *patch) {
    for (NSView *page in DPFindViews(DPDiaNewTabPage)) {
        DPCommandBarOverlay *overlay = DPGet(page, &DPOverlayKey);
        BOOL blank = DPGet(page, &DPBlankKey) != nil;
        if (blank && !page.hidden) return @"a blank tab shows its new tab page";
        if (DPCommandBar.on && !overlay && !blank && !DPGet(page, &DPOwnBarKey)) return @"a new tab page shows without the bar over it";
        if (overlay && overlay.panel.superview != overlay) return @"the bar isn't on the overlay";
    }
    for (NSWindow *window in NSApp.windows) {
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        NSString *standIn = DPVerifyStandIn(window, DPTabID(overlay.openedTab));
        if (standIn) return standIn;
        if (!overlay) continue;
        if (!DPCommandBar.on) return @"the bar is still open";
        BOOL hasShadow = overlay.panel.shadow != nil;
        if (DPCommandBarShadow.on && !hasShadow) return @"the bar has no shadow";
        if (!DPCommandBarShadow.on && hasShadow) return @"the bar still has a shadow";
        if (overlay.superview != window.contentView) return @"the bar is outside the content view, where hovering can't highlight suggestions";
        NSString *active = DPActiveTabID(window);
        if (overlay.openedTab && active && ![active isEqual:DPTabID(overlay.openedTab)] && ![active isEqual:DPTabID(overlay.returnTab)])
            return @"the bar stays over a tab it wasn't opened for";
    }
    return nil;
}

static void DPInstallCommandBar(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPCommandBarKey(event); }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSWindow *window = note.object;
        DPForgetSpare(window);
        DPClearCatchUp(window);
        DPCommandBarOverlay *old = DPTakeHandOver(window);
        if (old) DPNoteSpare(DPTabID(DPDismiss(old, NO)), NO);
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (overlay) DPNoteSpare(DPTabID(DPDismiss(overlay, NO)), NO);
    }];
    DPInstallAutoPipHold();
    DPHook(DPDiaPopover, @selector(viewDidMoveToWindow), (IMP)DPPopover_viewDidMoveToWindow);
    DPHook(DPDiaPopover, @selector(hitTest:), (IMP)DPPopover_hitTest);
    DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabButton_mouseDown);
    DPHook(DPDiaTabSurfaceButton, @selector(mouseDown:), (IMP)DPPlusButton_mouseDown);
    DPHook(DPDiaTabList, @selector(handleBackgroundDoubleClick:), (IMP)DPTabList_backgroundDoubleClick);
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
    DPHook(DPDiaTabList, @selector(viewDidMoveToWindow), (IMP)DPTabList_viewDidMoveToWindow);
    DPHook(DPDiaTabStripTabs, @selector(viewDidMoveToWindow), (IMP)DPStrip_viewDidMoveToWindow);
    DPHook(DPDiaNewTabPage, @selector(viewDidMoveToWindow), (IMP)DPNewTabPage_viewDidMoveToWindow);
    DPHook(DPDiaAssistantPanel, @selector(setFrame:), (IMP)DPPanel_setFrame);
    DPHook(DPDiaCommandBarSuggestions, @selector(invalidateIntrinsicContentSize), (IMP)DPSuggestions_invalidateIntrinsicContentSize);
    DPHook(DPDiaCapabilityButton, @selector(mouseDown:), (IMP)DPCapability_mouseDown);
}

#pragma mark Settings rows

@interface DPCommandBarTuneRow : NSStackView <NSTextFieldDelegate>
@property(copy) NSString *key;
@property double scale;
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPCommandBarTuneRow

- (void)tune:(NSControl *)control {
    double shown = [control isKindOfClass:NSSwitch.class] ? ((NSSwitch *)control).state
                                                          : round(MIN(MAX(control.doubleValue, 0), self.slider.maxValue));
    self.slider.doubleValue = shown;
    self.field.doubleValue = shown;
    [DPSettings() setDouble:shown / self.scale forKey:self.key];
    for (NSWindow *window in NSApp.windows) {
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (overlay) DPShowShade(overlay);
        overlay.needsLayout = YES;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    static NSDictionary<NSString *, NSNumber *> *steps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        steps = @{ @"moveUp:" : @1, @"moveDown:" : @-1, @"moveUpAndModifySelection:" : @10, @"moveDownAndModifySelection:" : @-10 };
    });
    NSNumber *step = steps[NSStringFromSelector(command)];
    if (!step) return NO;
    self.field.doubleValue = textView.string.doubleValue + step.doubleValue;
    [self tune:self.field];
    [textView selectAll:nil];
    return YES;
}

@end

static DPCommandBarTuneRow *DPTuneRow(NSString *title, NSString *key, double scale, NSView *control) {
    NSTextField *label = [NSTextField labelWithString:title];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    DPCommandBarTuneRow *row = [DPCommandBarTuneRow stackViewWithViews:@[ label, control ]];
    row.key = key;
    row.scale = scale;
    return row;
}

static NSView *DPSliderRow(NSString *title, NSString *key, double max, double scale, NSString *unit) {
    double shown = round(DPTuned(key) * scale);
    NSSlider *slider = [NSSlider sliderWithValue:shown minValue:0 maxValue:max target:nil action:@selector(tune:)];
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = whole;
    field.doubleValue = shown;
    field.alignment = NSTextAlignmentRight;
    field.action = @selector(tune:);
    [field.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ slider, field, [NSTextField labelWithString:unit] ]];

    DPCommandBarTuneRow *row = DPTuneRow(title, key, scale, controls);
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    row.slider = slider;
    row.field = field;
    slider.target = field.target = field.delegate = row;
    return row;
}

static NSView *DPSwitchRow(NSString *title, NSString *key) {
    NSSwitch *toggle = [NSSwitch new];
    toggle.state = DPTuned(key) ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.action = @selector(tune:);
    DPCommandBarTuneRow *row = DPTuneRow(title, key, 1, toggle);
    row.distribution = NSStackViewDistributionFill;
    toggle.target = row;
    return row;
}

static NSArray<NSView *> *DPCommandBarRows(void) {
    NSView *darkness = DPSliderRow(@"Darkness", DPDarknessKey, 80, 100, @"%"), *radius = DPSliderRow(@"Blur Radius", DPBlurRadiusKey, 60, 1, @"pt"),
           *sidebar = DPSwitchRow(@"Blur Sidebar Too", DPBlurWindowKey),
           *intensity = DPSliderRow(@"Shadow Intensity", DPShadowIntensityKey, 80, 100, @"%");
    darkness.identifier = @"Darken";
    radius.identifier = sidebar.identifier = @"Blur";
    intensity.identifier = @"Shadow";
    return @[ DPSliderRow(@"Space Above Bar", DPHeightKey, 50, 100, @"%"), radius, sidebar, darkness, intensity ];
}

static NSMenu *DPCommandBarPositions(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Position"];
    for (NSArray *item in @[ @[ @"Like Spotlight", @"macos" ], @[ @"Center of Window", @"window" ], @[ @"Center of Page", @"page" ] ]) {
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:item[0] action:nil keyEquivalent:@""];
        entry.representedObject = item[1];
        [menu addItem:entry];
    }
    return menu;
}

DP_PATCH(DPCommandBar) {
    .key = @"commandBar",
    .order = 87,
    .title = @"Open New Tabs in Command Bar",
    .detail = @"Open new tabs as Dia’s command bar over the current page, like Arc. Choose a result to open it in a new tab, or press Escape or ⌘T again to go back.",
    .symbol = @"command.square.fill",
    .tint = @"systemOrangeColor",
    .section = @"Command Bar",
    .classes = DPClasses(DPDiaContentPane, DPDiaNewTabPage, DPDiaAssistantPanel, DPDiaCommandBarSuggestions),
    .choice = @"commandBarPosition",
    .defaultChoice = @"macos",
    .choices = DPCommandBarPositions,
    .rows = DPCommandBarRows,
    .install = DPInstallCommandBar,
    .apply = DPApplyCommandBar,
    .verify = DPVerifyCommandBar,
};

DP_PATCH(DPCommandBarBlur) {
    .key = @"commandBarBlur",
    .defaultOn = YES,
    .order = 88,
    .title = @"Blur Page Behind",
    .detail = @"Blur the page behind the command bar.",
    .symbol = @"aqi.medium",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Blur",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarDarken) {
    .key = @"commandBarDarken",
    .defaultOn = YES,
    .order = 89,
    .title = @"Darken Page Behind",
    .detail = @"Darken the page behind the command bar.",
    .symbol = @"moon.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Darken",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarShadow) {
    .key = @"commandBarShadow",
    .defaultOn = YES,
    .order = 90,
    .title = @"Shadow Behind Bar",
    .detail = @"Add a shadow behind the command bar so it stands out when Blur and Darken are off, like Arc.",
    .symbol = @"shadow rectangle.fill.on.rectangle.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Shadow",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarInteractive) {
    .key = @"commandBarInteractive",
    .defaultOn = YES,
    .order = 91,
    .title = @"Scroll Page Behind",
    .detail = @"Scroll the page behind the command bar while it's open, like Arc. The pointer doesn't highlight it, and clicking outside closes the bar without clicking the page.",
    .symbol = @"cursorarrow.rays",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Interaction",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarKeepText) {
    .key = @"commandBarKeepText",
    .order = 92,
    .title = @"Remember What You Typed",
    .detail = @"Bring back what you typed when you open the bar again after Escape, selected so you can carry on or type over it.",
    .symbol = @"text.cursor",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Typing",
};
