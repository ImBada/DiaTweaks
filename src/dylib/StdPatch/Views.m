#import "StdPatch/StdPatch.h"
#import <os/log.h>
#import <stdatomic.h>

// Hot hooks look Dia's classes up by name on every call; the slot is only a hint, checked against the class's own name.
static Class DPClassNamed(const char *name) {
    static _Atomic(void *) cache[256];
    uint32_t hash = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)name; *p; p++) hash = (hash ^ *p) * 16777619u;
    _Atomic(void *) *slot = &cache[hash & 255];
    Class cls = (__bridge Class)atomic_load_explicit(slot, memory_order_relaxed);
    if (cls && !strcmp(class_getName(cls), name)) return cls;
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

NSArray<NSView *> *DPFindViews(const char *className) {
    Class cls = className ? DPClassNamed(className) : Nil;
    if (!cls) return @[];
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows)
        if (window.isVisible) DPCollectViews(window.contentView, cls, views);
    return views;
}

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

BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel) {
    return [view.accessibilityLabel isEqualToString:accessibilityLabel];
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
