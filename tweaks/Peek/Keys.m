#import "Peek.h"
#import <Carbon/Carbon.h>

static BOOL DPIsDigitKey(NSEvent *event) {
    NSString *key = event.charactersIgnoringModifiers;
    return key.length == 1 && [key characterAtIndex:0] >= '1' && [key characterAtIndex:0] <= '9';
}

static BOOL DPPerformAppShortcut(NSEvent *event, NSEventModifierFlags mods) {
    if (!(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) return NO;
    return [NSApp.mainMenu.itemArray.firstObject.submenu performKeyEquivalent:event] || [NSApp.windowsMenu performKeyEquivalent:event];
}

// Blink ignores key-equivalent paste/undo while swallowing ⌘/⌃ shortcuts, so dispatch edit actions directly to focus.
static BOOL DPPeekPageShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods, NSResponder *focus) {
    BOOL command = mods == NSEventModifierFlagCommand, shifted = mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift);
    SEL edit = NULL;
    if (command && DPEventIsKey(event, @"x")) edit = @selector(cut:);
    else if (command && DPEventIsKey(event, @"c")) edit = @selector(copy:);
    else if (command && DPEventIsKey(event, @"v")) edit = @selector(paste:);
    else if (command && DPEventIsKey(event, @"a")) edit = @selector(selectAll:);
    else if (command && DPEventIsKey(event, @"z")) edit = @selector(undo:);
    else if (shifted && DPEventIsKey(event, @"z")) edit = @selector(redo:);
    else if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift) && DPEventIsKey(event, @"v")) edit = @selector(pasteAsPlainText:);
    return edit && [focus respondsToSelector:edit] && [NSApp sendAction:edit to:focus from:nil];
}

static NSMenuItem *DPPeekItemFor(NSMenu *menu, NSEvent *event) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = DPPeekIsShortcut(event, item) ? item : DPPeekItemFor(item.submenu, event);
        if (found) return found;
    }
    return nil;
}

static BOOL DPPeekWindowCommand(NSEvent *event) {
    if (!(event.modifierFlags & NSEventModifierFlagCommand)) return NO;
    NSString *title = DPPeekItemFor(NSApp.mainMenu, event).title;
    return [title isEqualToString:@"New Tab"] || [title isEqualToString:@"New Window"] || [title isEqualToString:@"New Incognito Window"];
}

static BOOL DPPeekCoveredByCommandBar(NSWindow *window) {
    Class overlay = NSClassFromString(@"DPCommandBarOverlay");
    if (!overlay) return NO;
    for (NSView *sub in window.contentView.subviews)
        if ([sub isKindOfClass:overlay] && !sub.isHiddenOrHasHiddenAncestor) return YES;
    return NO;
}

static BOOL DPPeekExternalTextFocus(DPPeekCard *peek, id responder) {
    if (![responder isKindOfClass:NSView.class] || [(NSView *)responder isDescendantOf:peek]) return NO;
    if ([responder isKindOfClass:NSText.class]) return YES;
    for (NSView *view = responder; view; view = view.superview)
        if (DPIsKind(view, DPDiaCommandBar) || DPIsKind(view, DPDiaAddressField)) return YES;
    return NO;
}

static BOOL DPPeekYieldsToOverlay(NSWindow *window) {
    if (window.attachedSheet || DPPeekCoveredByCommandBar(window)) return YES;
    return DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaPopover) && !view.isHiddenOrHasHiddenAncestor && !DPIsFloatingChat(view);
    }) != nil;
}

NSEvent *DPPeekHandleKeyEvent(DPPeekCard *peek, NSEvent *event) {
    if (!peek || !DPPeek.on || event.window != peek.window || DPPeekYieldsToOverlay(event.window)) return event;
    DPPeekSyncTabs(event.window);
    if (DPPeekCardIn(event.window) != peek) return event;
    NSEventModifierFlags mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad);
    id responder = peek.window.firstResponder;
    if (DPPeekResponderInChat(responder) || DPPeekExternalTextFocus(peek, responder)) return event;
    BOOL command = mods == NSEventModifierFlagCommand, control = mods == NSEventModifierFlagControl;
    // A page's field is not an NSText; Escape there must cancel an input method's composition, not close the card.
    BOOL editing = [responder isKindOfClass:NSText.class] || ([responder conformsToProtocol:@protocol(NSTextInputClient)] && [responder hasMarkedText]);
    BOOL onPage = [responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:peek.host];
    if (DPPeekCopyURL(peek, event) || DPPeekZoomShortcut(peek, event) || DPPeekFindShortcut(peek, event, mods)) return nil;
    if (onPage && DPPeekPageShortcut(peek, event, mods, responder)) return nil;
    if (DPPeekChatShortcut(peek, event, mods)) return nil;
    if (command && DPEventIsKey(event, @"o")) [peek close:DPPeekTab];
    else if (command && peek.toolbar && DPEventIsKey(event, @"[")) DPPeekNavigate(peek.page, DPPeekBack);
    else if (command && peek.toolbar && DPEventIsKey(event, @"]")) DPPeekNavigate(peek.page, DPPeekForward);
    else if (command && peek.toolbar && DPEventIsKey(event, @"r")) DPPeekNavigate(peek.page, DPPeekReload);
    else if (command && peek.toolbar && DPEventIsKey(event, @"l")) DPPeekEditToolbarAddress(peek);
    else if ((command && DPEventIsKey(event, @"w")) || (!mods && event.keyCode == kVK_Escape && !editing)) [peek close:DPPeekClose];
    else if (!DPPerformAppShortcut(event, mods)) {
        BOOL toMenu = (command && DPEventIsKey(event, @"s")) ||
                      (onPage ? (mods & NSEventModifierFlagControl) || DPPeekWindowCommand(event) : control && DPIsDigitKey(event));
        if (!(toMenu && [NSApp.mainMenu performKeyEquivalent:event])) return event;
    }
    return nil;
}

id DPPeekWatchKeys(DPPeekCard *card) {
    __weak DPPeekCard *weak = card;
    return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return DPPeekHandleKeyEvent(weak, event);
    }];
}
