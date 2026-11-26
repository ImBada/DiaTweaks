#import "Patches/Peek/Peek.h"
#import "Patches/HideToolbar/HideToolbar.h"

static NSMenuItem *DPPeekMenuItem(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPPeekMenuItem(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item) {
    NSString *key = item.keyEquivalent;
    if (!key.length) return NO;
    NSEventModifierFlags all = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;
    NSEventModifierFlags mask = item.keyEquivalentModifierMask & all, held = event.modifierFlags & all;
    // A capital key equivalent implies Shift; ⌘+ matches without it, as the menu does.
    if (![key isEqual:key.lowercaseString]) mask |= NSEventModifierFlagShift;
    if ([key isEqual:@"+"]) mask &= ~NSEventModifierFlagShift, held &= ~NSEventModifierFlagShift;
    return held == mask && DPEventIsKey(event, key);
}

// Weak so a test can hand back a scratch pasteboard and leave the real clipboard alone.
__attribute__((weak)) NSPasteboard *DPPeekPasteboard(void) { return NSPasteboard.generalPasteboard; }

BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event) {
    BOOL markdown = DPPeekIsShortcut(event, DPPeekMenuItem(NSApp.mainMenu, @"Copy URL as Markdown"));
    if (!markdown && !DPPeekIsShortcut(event, DPPeekMenuItem(NSApp.mainMenu, @"Copy URL"))) return NO;
    NSURL *url = DPValueForKey(peek.page, @"url");
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *title = DPValueForKey(peek.page, @"title");
    if (![title isKindOfClass:NSString.class] || !title.length) title = url.absoluteString;
    NSPasteboard *board = DPPeekPasteboard();
    [board clearContents];
    if (markdown) [board setString:[NSString stringWithFormat:@"[%@](%@)", title, url.absoluteString] forType:NSPasteboardTypeString];
    else {
        [board setString:url.absoluteString forType:NSPasteboardTypeString];
        [board setString:url.absoluteString forType:NSPasteboardTypeURL];
    }
    DPShowCopyToast(peek.clip, markdown ? @"Copied URL as Markdown" : @"Copied Current URL");
    return YES;
}
