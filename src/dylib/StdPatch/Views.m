#import "StdPatch/StdPatch.h"
#import <os/log.h>
#import <pthread.h>
#import <stdatomic.h>

// Swift registers "Module.Class" as "_TtC<len>Module<len>Class", so a dotted lookup name never equals the class's own name.
static BOOL DPSameClassName(const char *actual, const char *name) {
    if (!strcmp(actual, name)) return YES;
    if (strncmp(actual, "_TtC", 4)) return NO;
    actual += 4;
    for (int part = 0; part < 2; part++) {
        if (*actual < '1' || *actual > '9') return NO;
        size_t length = 0;
        while (*actual >= '0' && *actual <= '9' && length <= 256) length = length * 10 + (size_t)(*actual++ - '0');
        if (length > 256) return NO;
        for (; length; length--, actual++, name++)
            if (!*actual || *actual != *name) return NO;
        if (part == 0 ? *name++ != '.' : *name) return NO;
    }
    return !*actual;
}

// Hot hooks look Dia's classes up by name on every call; the slot is only a hint, checked against the class's own name.
static Class DPClassNamed(const char *name) {
    static _Atomic(void *) cache[256];
    uint32_t hash = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)name; *p; p++) hash = (hash ^ *p) * 16777619u;
    _Atomic(void *) *slot = &cache[hash & 255];
    Class cls = (__bridge Class)atomic_load_explicit(slot, memory_order_relaxed);
    if (cls && DPSameClassName(class_getName(cls), name)) return cls;
    cls = objc_getClass(name);
    if (cls) atomic_store_explicit(slot, (__bridge void *)cls, memory_order_relaxed);
    return cls;
}

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *)) {
    if (!root || match(root)) return root;
    for (NSView *sub in root.subviews) {
        NSView *found = DPFindView(sub, match);
        if (found) return found;
    }
    return nil;
}

static void DPCollectViews(NSView *view, Class cls, NSMutableArray<NSView *> *views) {
    if ([view isKindOfClass:cls]) [views addObject:view];
    for (NSView *sub in view.subviews) DPCollectViews(sub, cls, views);
}

static NSArray<NSView *> *DPViewsOfClass(const char *className, BOOL hiddenToo) {
    Class cls = className ? DPClassNamed(className) : Nil;
    if (!cls) return @[];
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows)
        if (hiddenToo || window.isVisible) DPCollectViews(window.contentView, cls, views);
    return views;
}

NSArray<NSView *> *DPFindViews(const char *className) { return DPViewsOfClass(className, NO); }

NSArray<NSView *> *DPFindAllViews(const char *className) { return DPViewsOfClass(className, YES); }

NSString *DPTabLayout(void) {
    Class cls = DPClassNamed(DPDiaSidebarFooter);
    if (cls)
        for (NSWindow *window in NSApp.windows)
            if (window.isVisible && DPFindView(window.contentView, ^BOOL(NSView *v) { return [v isKindOfClass:cls]; })) return @"vertical";
    return @"horizontal";
}

NSView *DPSubview(NSView *parent, const char *className) {
    Class cls = parent && className ? DPClassNamed(className) : Nil;
    if (!cls) return nil;
    for (NSView *sub in parent.subviews) if ([sub isKindOfClass:cls]) return sub;
    return nil;
}

BOOL DPIsKind(id object, const char *className) {
    if (!object || !className) return NO;
    Class cls = DPClassNamed(className);
    return cls && [object isKindOfClass:cls];
}

BOOL DPIsFloatingChat(NSView *popover) {
    Class cls = popover ? DPClassNamed(DPDiaChatHeader) : Nil;
    return cls && DPFindView(popover, ^BOOL(NSView *view) { return [view isKindOfClass:cls]; }) != nil;
}

// Dia 1.58.1+ replaces the Ask button's tooltip with an intro popover, dropping its accessibility label.
BOOL DPIsChatButton(NSView *view) {
    if (DPHasLabel(view, @"Chat with this tab")) return YES;
    if (!DPIsKind(view, DPDiaCapsuleButton)) return NO;
    return ([view isKindOfClass:NSControl.class] && ((NSControl *)view).action == @selector(didClickAskButton:))
        || [view.toolTip isEqualToString:@"Chat with this tab"]
        || DPFindView(view, ^BOOL(NSView *sub) { return DPHasLabel(sub, @"chat fill"); }) != nil;
}

static __unsafe_unretained NSView *DPLabelView;
static NSString *DPLabel;
static BOOL DPLabelRead;

void DPShareLabel(NSView *view) {
    DPLabelView = pthread_main_np() ? view : nil;
    DPLabel = nil;
    DPLabelRead = NO;
}

BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel) {
    if (!view || view != DPLabelView || !pthread_main_np()) return [view.accessibilityLabel isEqualToString:accessibilityLabel];
    if (!DPLabelRead) {
        DPLabel = view.accessibilityLabel;
        DPLabelRead = YES;
    }
    return [DPLabel isEqualToString:accessibilityLabel];
}

void DPRelayoutViews(NSHashTable<NSView *> *views) {
    for (NSView *view in views.allObjects) {
        view.needsLayout = YES;
        [view layoutSubtreeIfNeeded];
    }
}

static const NSUInteger DPAdjustLimit = 8;

BOOL DPMayAdjust(NSView *view) {
    static NSMapTable<NSView *, NSNumber *> *counts;
    if (!counts) {
        counts = [NSMapTable weakToStrongObjectsMapTable];
        CFRunLoopObserverRef reset = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
            [counts removeAllObjects];
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), reset, kCFRunLoopCommonModes);
    }
    NSUInteger n = [[counts objectForKey:view] unsignedIntegerValue] + 1;
    [counts setObject:@(n) forKey:view];
    if (n == DPAdjustLimit + 1) {
        os_log(OS_LOG_DEFAULT, "DiaPatches: letting Dia lay out %{public}s for the rest of this turn, which kept undoing a patch", object_getClassName(view));
        // A busy run loop never waits to reset the counts, so retry soon.
        __weak NSView *weak = view;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) [counts removeObjectForKey:weak];
            for (NSView *up = weak; up; up = up.superview) up.needsLayout = YES;
        });
    }
    return n <= DPAdjustLimit;
}

void *DPIvar(id object, const char *name) {
    Ivar ivar = object && name ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar ? (uint8_t *)(__bridge void *)object + ivar_getOffset(ivar) : NULL;
}

@interface NSObject (DPSwiftValue)
- (id)safeSwiftValueForKey:(NSString *)key;
@end

id DPSwiftValue(id object, NSString *key) {
    return [object respondsToSelector:@selector(safeSwiftValueForKey:)] ? [object safeSwiftValueForKey:key] : nil;
}

NSMenu *DPTabContextMenu(NSView *tab) {
    NSPoint point = [tab convertPoint:NSMakePoint(NSMidX(tab.bounds), NSMidY(tab.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:tab.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    return [tab menuForEvent:click];
}

id DPTabState(NSView *tab) {
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue");
}

// selectionStyle is nil on an unselected pinned tab, "none" on other unselected tabs, above/below beside the selection.
BOOL DPStateSelected(id state) {
    NSString *style = [[DPSwiftValue(state, @"selectionStyle") description] lowercaseString];
    return style && ![style isEqualToString:@"nil"] && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

NSView *DPFindTabIn(NSWindow *window, BOOL (^match)(NSView *tab)) {
    const char *kinds[2] = {DPDiaTabView, DPDiaPinnedTab};
    for (int i = 0; i < 2; i++)
        for (NSView *tab in DPFindViews(kinds[i]))
            if ((!window || tab.window == window) && !tab.isHiddenOrHasHiddenAncestor && match(tab)) return tab;
    return nil;
}

NSString *DPPageID(id page) {
    static NSString *const keys[] = {@"identifier", @"id", @"contentID", @"contentId", @"uuid"};
    for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) {
        NSString *value = [DPSwiftValue(page, keys[i]) description];
        if (value.length >= 32 && [value containsString:@"-"]) return value;
    }
    return nil;
}

NSView *DPTabShowing(NSWindow *window, NSString *pageID, BOOL anyWindow) {
    __block NSView *selected = nil;
    NSView *exact = DPFindTabIn(anyWindow ? nil : window, ^BOOL(NSView *tab) {
        id state = DPTabState(tab);
        if (pageID && [[state description] containsString:pageID]) return YES;
        if (!selected && (!window || tab.window == window) && DPStateSelected(state)) selected = tab;
        return NO;
    });
    return exact ?: selected;
}

static char DPPinnedRowKey;

// Icon tiles' links already open new tabs; a pinned row's don't, and only its context menu says it is pinned.
// Several hooks ask about the same click and the menu is costly to build, so an answer holds for half a second.
BOOL DPPageInPinnedRow(NSWindow *window, id page) {
    NSArray *memo = page ? DPGet(page, &DPPinnedRowKey) : nil;
    CFTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (memo && [memo[2] nonretainedObjectValue] == window && now - [memo[1] doubleValue] < 0.5) return [memo[0] boolValue];
    NSView *tab = DPTabShowing(window, DPPageID(page), YES);
    NSMenuItem *unpin = tab && !DPIsKind(tab, DPDiaPinnedTab) ? [DPTabContextMenu(tab) itemWithTitle:@"Unpin"] : nil;
    BOOL pinned = unpin && !unpin.hidden && unpin.enabled;
    if (page) DPSet(page, &DPPinnedRowKey, @[ @(pinned), @(now), [NSValue valueWithNonretainedObject:window] ]);
    return pinned;
}

BOOL DPIsWebURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *scheme = url.scheme;
    return [scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame;
}

@interface DPStayingAction : NSProxy
@property (nonatomic, strong) id action;
@end

@implementation DPStayingAction
- (NSInteger)navigationDisposition { return DPCurrentTab; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.action methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.action]; }
- (BOOL)respondsToSelector:(SEL)selector { return selector == @selector(navigationDisposition) || [self.action respondsToSelector:selector]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [self.action conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [self.action isKindOfClass:cls]; }
@end

id DPActionStayingInTab(id action) {
    DPStayingAction *staying = [DPStayingAction alloc];
    staying.action = action;
    return staying;
}

NSArray<NSString *> *DPUUIDsIn(NSString *text) {
    if (!text.length) return @[];
    static NSRegularExpression *uuid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ uuid = [NSRegularExpression regularExpressionWithPattern:@"[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}" options:0 error:nil]; });
    NSMutableArray *found = [NSMutableArray new];
    for (NSTextCheckingResult *match in [uuid matchesInString:text options:0 range:NSMakeRange(0, text.length)])
        [found addObject:[text substringWithRange:match.range]];
    return found;
}

NSWindowController *DPOpenTabSwitcher(void) {
    Class cls = DPClassNamed(DPDiaTabSwitcher);
    if (!cls) return nil;
    for (NSWindow *window in NSApp.windows)
        if (window.visible && [window.windowController isKindOfClass:cls]) return window.windowController;
    return nil;
}

id DPGet(id object, const void *key) {
    return objc_getAssociatedObject(object, key);
}

void DPSet(id object, const void *key, id value) {
    objc_setAssociatedObject(object, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DPOverride(id object, const void *key, id dia, id ours) {
    if (!object || !dia || !ours) return;
    NSArray *current = DPGet(object, key);
    if (current && [current[0] isEqual:dia] && [current[1] isEqual:ours]) return;
    DPSet(object, key, @[dia, ours]);
}

id DPDiaValue(id object, const void *key, id current) {
    NSArray *values = DPGet(object, key);
    return values && [values[1] isEqual:current] ? values[0] : current;
}
