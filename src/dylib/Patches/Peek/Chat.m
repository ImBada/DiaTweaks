#import "Patches/Peek/Peek.h"

@interface DPPeekCard (ChatLayout)
- (void)followPane;
@end

static BOOL DPPeekIsChatControl(NSView *view) {
    return DPIsChatButton(view) || DPIsKind(view, DPDiaPinnedExtension);
}

static NSView *DPPeekVisibleToolbar(NSView *pane) {
    NSView *bar = DPSubview(pane, DPDiaToolbar) ?: DPFindView(pane, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaToolbar); });
    return bar && !bar.isHiddenOrHasHiddenAncestor && bar.alphaValue > 0.05 ? bar : nil;
}

NSView *DPPeekChatHolder(NSWindow *window, NSView *pane) {
    NSView *prev = nil;
    for (NSView *view = pane; view && view != window.contentView; prev = view, view = view.superview)
        if ([NSStringFromClass(view.class) containsString:@"AssistantSidebarContentContainerView"])
            return prev && prev != pane ? prev : view;
    return nil;
}

static id DPPeekObserveFrame(DPPeekCard *peek, NSView *view) {
    __weak DPPeekCard *weak = peek;
    view.postsFrameChangedNotifications = YES;
    return [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:view queue:nil
                                                       usingBlock:^(NSNotification *note) { [weak followPane]; }];
}

NSArray *DPPeekWatchPaneAncestors(DPPeekCard *peek, NSView *pane, NSView *holder) {
    NSMutableArray *tokens = [NSMutableArray array];
    BOOL sawHolder = NO;
    for (NSView *view = pane; view; view = view.superview) {
        [tokens addObject:DPPeekObserveFrame(peek, view)];
        if (view == holder) { sawHolder = YES; break; }
    }
    if (holder && !sawHolder) [tokens addObject:DPPeekObserveFrame(peek, holder)];
    return tokens;
}

void DPPeekUnwatchPane(id observer) {
    if ([observer isKindOfClass:NSArray.class])
        for (id token in (NSArray *)observer) [NSNotificationCenter.defaultCenter removeObserver:token];
    else if (observer) [NSNotificationCenter.defaultCenter removeObserver:observer];
}

BOOL DPPeekAllowsPaneClick(DPPeekCard *peek, NSPoint pointInSuperview) {
    if (!DPPeek.on || !peek || peek.closing || !peek.pane || !peek.superview) return NO;
    NSView *bar = DPPeekVisibleToolbar(peek.pane);
    if (!bar || !bar.superview) return NO;
    NSPoint inBarSuper = [bar.superview convertPoint:pointInSuperview fromView:peek.superview];
    for (NSView *view = [bar hitTest:inBarSuper]; view && view != peek.pane; view = view.superview)
        if (!view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0.05 && DPPeekIsChatControl(view)) return YES;
    return NO;
}

NSRect DPPeekControlsFrame(DPPeekCard *peek, NSRect controlsFrame) {
    if (!DPPeek.on || !peek || !peek.pane) return controlsFrame;
    NSView *bar = DPPeekVisibleToolbar(peek.pane);
    if (!bar) return controlsFrame;
    NSView *chat = DPFindView(bar, ^BOOL(NSView *view) {
        return !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0.05 && DPPeekIsChatControl(view) &&
               NSIntersectsRect([peek convertRect:view.bounds fromView:view], NSInsetRect(controlsFrame, -4, -4));
    });
    if (!chat) return controlsFrame;
    NSRect hit = [peek convertRect:chat.bounds fromView:chat];
    CGFloat maxY = MAX(0, NSHeight(peek.bounds) - NSHeight(controlsFrame) - 8);
    controlsFrame.origin.y = MIN(maxY, MAX(controlsFrame.origin.y, NSMaxY(hit) + 8));
    return controlsFrame;
}

static BOOL DPPeekIsChatClassName(Class cls) {
    if (!cls) return NO;
    NSString *name = NSStringFromClass(cls);
    return [name containsString:@"ExtensionSidePanel"] || [name containsString:@"AssistantPanel"];
}

BOOL DPPeekResponderInChat(id responder) {
    if (![responder isKindOfClass:NSView.class]) return NO;
    for (NSView *view = responder; view; view = view.superview) {
        if (DPIsKind(view, DPDiaAssistantPanel) || DPIsKind(view, DPDiaChatHeader)) return YES;
        if (DPIsKind(view, DPDiaPopover) && DPIsFloatingChat(view)) return YES;
        if (DPPeekIsChatClassName(view.class) || DPPeekIsChatClassName([view.nextResponder class])) return YES;
    }
    return NO;
}

static BOOL DPPeekIsChatTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || [title hasPrefix:@"Chat with Support"]) return NO;
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = [NSSet setWithArray:@[ @"Chat…", @"Chat", @"Toggle Chat", @"Show Chat", @"Hide Chat",
                                        @"New Chat", @"Focus Chat", @"Send Chat Prompt Now" ]];
    });
    if ([titles containsObject:title]) return YES;
    NSStringCompareOptions prefix = NSCaseInsensitiveSearch | NSAnchoredSearch;
    return [title rangeOfString:@"chat with " options:prefix].location != NSNotFound
        || [title rangeOfString:@"ask dia" options:prefix].location != NSNotFound;
}

static NSMenuItem *DPPeekMenuItem(NSMenu *menu, NSEvent *event, BOOL inExtensions, BOOL *fromExtensions) {
    for (NSMenuItem *item in menu.itemArray) {
        if (DPPeekIsShortcut(event, item)) {
            if (fromExtensions) *fromExtensions = inExtensions;
            return item;
        }
        if (!item.submenu) continue;
        NSMenuItem *found = DPPeekMenuItem(item.submenu, event, inExtensions || [item.title isEqualToString:@"Extensions"], fromExtensions);
        if (found) return found;
    }
    return nil;
}

static BOOL DPPeekPressChatButton(DPPeekCard *peek) {
    NSView *bar = DPPeekVisibleToolbar(peek.pane);
    NSView *button = bar ? DPFindView(bar, ^BOOL(NSView *view) {
        return !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0.05 && DPIsChatButton(view);
    }) : nil;
    if (!button) return NO;
    if ([button isKindOfClass:NSControl.class] && ((NSControl *)button).action &&
        [NSApp sendAction:((NSControl *)button).action to:((NSControl *)button).target from:button]) return YES;
    return [button accessibilityPerformPress];
}

BOOL DPPeekChatShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods) {
    if (!DPPeek.on || !peek || peek.closing) return NO;
    if (!(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) return NO;
    BOOL inExtensions = NO;
    NSMenuItem *item = DPPeekMenuItem(NSApp.mainMenu, event, NO, &inExtensions);
    if (item) {
        BOOL chat = DPPeekIsChatTitle(item.title);
        if (!chat && !inExtensions) return NO;
        if (item.hidden) return NO;
        if ([NSApp.mainMenu performKeyEquivalent:event]) return YES;
        return chat && DPPeekPressChatButton(peek);
    }
    return mods == NSEventModifierFlagCommand && DPEventIsKey(event, @"e") && DPPeekPressChatButton(peek);
}

static void DPPeekSyncChatLayout(NSWindow *window) {
    DPPeekCard *peek = DPPeek.on ? DPPeekCardIn(window) : nil;
    if (!peek) return;
    [peek followPane];
    peek.needsLayout = YES;
}

static void DPAssistantSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPAssistantSidebar_viewWillLayout, self);
    if (!DPPeek.on) return;
    NSWindow *window = self.view.window;
    if (!window || !DPPeekCardIn(window)) return;
    DPPeekSyncChatLayout(window);
    __weak NSWindow *weakWindow = window;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DPPeek.on && weakWindow) DPPeekSyncChatLayout(weakWindow);
    });
}

static void DPAssistantLayout_resized(id self, SEL _cmd, NSNotification *note) {
    DPCallOriginal(DPAssistantLayout_resized, self, note);
    if (!DPPeek.on) return;
    NSView *view = [note.object isKindOfClass:NSView.class] ? note.object : nil;
    if (view.window && DPPeekCardIn(view.window)) DPPeekSyncChatLayout(view.window);
}

void DPPeekInstallChat(void) {
    DPPeekInstallChatContext();
    DPHook(DPDiaAssistantSidebar, @selector(viewWillLayout), (IMP)DPAssistantSidebar_viewWillLayout);
    DPHook(DPDiaAssistantSidebarLayout, @selector(containerViewResized:), (IMP)DPAssistantLayout_resized);
}
