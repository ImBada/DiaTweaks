#import "SidebarAddressBar.h"
#import "WindowTabs.h"
#import <objc/message.h>

// Check selectors before reading Dia's private scripting facade. A changed facade leaves an empty row.
static id DPRead(id object, NSString *key) {
    SEL selector = NSSelectorFromString(key);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

NSString *DPSidebarTabIdentifier(NSWindow *window) { return DPWindowTabIdentifier(window); }

BOOL DPSidebarNavigate(NSWindow *window, NSString *address) {
    if (!window) return NO;
    NSString *value = [address stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length || [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return NO;
    if (![value containsString:@"://"]) value = [@"https://" stringByAppendingString:value];
    NSURLComponents *parts = [NSURLComponents componentsWithString:value];
    if (!parts.URL || !parts.host.length ||
        ![@[@"https", @"http"] containsObject:parts.scheme.lowercaseString]) return NO;
    for (id scripted in DPRead(NSApp.delegate, @"appleScriptWindows")) {
        if (![DPRead(scripted, @"windowId") isEqual:window.identifier]) continue;
        id tab = DPRead(scripted, @"activeTab");
        SEL setter = NSSelectorFromString(@"setURL:");
        if (![tab respondsToSelector:setter]) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(tab, setter, parts.URL.absoluteString);
        return YES;
    }
    return NO;
}

NSString *DPSidebarDomain(NSString *url) {
    if (!url.length || [url isEqual:@"about:blank"] || [url hasPrefix:@"chrome://newtab"]) return @"Search or enter URL";
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    if ([parts.scheme.lowercaseString isEqual:@"file"]) return @"Local file";
    // Never show user info, query strings, or data URLs as a sidebar title.
    NSString *host = parts.host;
    if (host.length) {
        if (host.length > 4 && [host.lowercaseString hasPrefix:@"www."]) host = [host substringFromIndex:4];
        return host;
    }
    if ([parts.scheme.lowercaseString isEqual:@"about"]) return @"Browser page";
    return @"Current page";
}

static NSMenuItem *DPShortcutItem(NSMenu *menu, NSString *key) {
    for (NSMenuItem *item in menu.itemArray) {
        NSEventModifierFlags modifiers = item.keyEquivalentModifierMask & (NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                                                         NSEventModifierFlagControl | NSEventModifierFlagOption);
        if ([item.keyEquivalent.lowercaseString isEqual:key] && modifiers == NSEventModifierFlagCommand && item.action) return item;
        NSMenuItem *found = DPShortcutItem(item.submenu, key);
        if (found) return found;
    }
    return nil;
}

BOOL DPSidebarOpenEditor(NSView *anchor) {
    return DPSidebarOpenEditorWithQuery(anchor, nil);
}

static BOOL DPOpenSidebarEditor(NSView *anchor, NSString *query, BOOL anchored) {
    NSWindow *window = anchor.window;
    if (!window || window.attachedSheet) return NO;
    [window makeKeyAndOrderFront:nil];
    NSString *url = DPSidebarURL(window);
    BOOL empty = !url.length || [url isEqual:@"about:blank"] || [url hasPrefix:@"chrome://newtab"];
    BOOL inlineEmpty = query != nil && empty;
    if (query) empty = NO;
    NSMenuItem *item = DPShortcutItem(NSApp.mainMenu, empty ? @"t" : @"l");
    if (!item) return NO;
    if (anchored && !empty) DPSidebarRequestPopoverWithQuery(anchor, query);
    __weak NSWindow *host = window;
    NSString *key = [item.keyEquivalent copy];
    __weak NSView *weakAnchor = anchor;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!host || !host.isVisible || host.attachedSheet) return;
        if (query != nil && ![(DPSidebarAddressRow *)weakAnchor isEditingAddress]) return;
        // Let AppKit install the keyboard event as currentEvent before
        // dispatch. Calling sendEvent: on the window can leave the click
        // as currentEvent, and Dia then asks that mouse event for keyCode.
        for (NSNumber *type in @[@(NSEventTypeKeyDown), @(NSEventTypeKeyUp)]) {
            NSEvent *event = [NSEvent keyEventWithType:type.integerValue location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                           timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:host.windowNumber context:nil
                                          characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:empty ? 17 : 37];
            [NSApp postEvent:event atStart:NO];
        }
        if (inlineEmpty) {
            // Empty-tab command bars can already be attached to the content
            // pane, so their session never passes through the popover hook.
            dispatch_async(dispatch_get_main_queue(), ^{
                NSView *bar = DPFindView(host.contentView, ^BOOL(NSView *view) {
                    return DPIsKind(view, DPDiaCommandBar) && !view.hiddenOrHasHiddenAncestor;
                });
                NSView *input = DPFindView(bar, ^BOOL(NSView *view) {
                    return DPIsKind(view, DPDiaCommandBarText);
                });
                NSTextView *editor = (NSTextView *)DPFindView(input, ^BOOL(NSView *view) {
                    return [view isKindOfClass:NSTextView.class];
                });
                if (!editor || ![weakAnchor isKindOfClass:DPSidebarAddressRow.class]) return;
                DPSidebarAddressRow *row = (DPSidebarAddressRow *)weakAnchor;
                [row attachSuggestionSession:bar editor:editor];
                [row finishStartingSuggestionSession];
            });
        }
    });
    return YES;
}


BOOL DPSidebarOpenEditorWithQuery(NSView *anchor, NSString *query) {
    return DPOpenSidebarEditor(anchor, query, YES);
}

BOOL DPSidebarOpenDefaultEditor(NSView *anchor) {
    DPSidebarCancelPopoverRequest(anchor);
    return DPOpenSidebarEditor(anchor, nil, NO);
}
