#import "StdPatch/StdPatch.h"

extern DPPatch DPExtensionsShortcut;
static NSMapTable<NSWindow *, id> *DPBrowsers;
static id DPKeyMonitor;

static NSDictionary *DPDefaultExtensionsShortcut(void) {
    return @{ @"keyCode" : @7, @"modifiers" : @(NSEventModifierFlagShift | NSEventModifierFlagCommand), @"key" : @"X" };
}

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    if (window) [DPBrowsers setObject:self forKey:window];
}

// Chromium's icon can be blank, so prefer the pinned toolbar icon.
static NSImage *DPIconFor(id info, NSWindow *window) {
    id name = DPValueForKey(info, @"name");
    NSView *pinned = [name isKindOfClass:NSString.class] ? DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaPinnedExtension) && [view.accessibilityLabel isEqualToString:name];
    }) : nil;
    NSImage *icon = ((NSImageView *)DPFindView(pinned, ^BOOL(NSView *view) { return [view isKindOfClass:NSImageView.class]; })).image;
    id rawIcon = DPValueForKey(info, @"icon");
    icon = [icon ?: ([rawIcon isKindOfClass:NSImage.class] ? rawIcon : nil) ?: [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil] copy];
    icon.size = NSMakeSize(16, 16);
    return icon;
}

static NSString *DPExtensionName(id info) {
    id name = DPValueForKey(info, @"name");
    return [name isKindOfClass:NSString.class] ? name : @"";
}

static NSMenu *DPExtensionsMenu(id browser, NSWindow *window) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Extensions"];
    id context = [browser respondsToSelector:@selector(context)] ? [browser performSelector:@selector(context)] : nil;
    id extensions = [context respondsToSelector:@selector(extensions)] ? [context performSelector:@selector(extensions)] : nil;
    id raw = [extensions respondsToSelector:@selector(listExtensions)] ? [extensions performSelector:@selector(listExtensions)] : nil;
    NSArray *all = [raw isKindOfClass:NSArray.class] ? [raw sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [DPExtensionName(a) localizedCaseInsensitiveCompare:DPExtensionName(b)];
    }] : @[];
    for (id info in all) {
        if (![DPValueForKey(info, @"enabled") boolValue] || ![DPValueForKey(info, @"hasAction") boolValue]) continue;
        NSString *extensionID = DPValueForKey(info, @"id");
        NSMenuItem *item = DPMenuItem(DPExtensionName(info), ^{
            if (extensionID && [browser respondsToSelector:@selector(executeExtensionAction:)])
                [browser performSelector:@selector(executeExtensionAction:) withObject:extensionID];
        });
        item.image = DPIconFor(info, window);
        [menu addItem:item];
    }
    if (!menu.numberOfItems) [menu addItemWithTitle:@"No Extensions" action:nil keyEquivalent:@""];
    return menu;
}

static void DPShowExtensions(NSWindow *window, id browser) {
    NSView *content = window.contentView;
    if (!window.isVisible || !content) return;
    NSRect page = content.bounds;
    NSPoint corner = NSMakePoint(NSMaxX(page) - 240, content.isFlipped ? 48 : NSMaxY(page) - 48);
    [DPExtensionsMenu(browser, window) popUpMenuPositioningItem:nil atLocation:corner inView:content];
}

static void DPApplyExtensionsShortcut(DPPatch *patch) {
    DPSyncMonitor(&DPKeyMonitor, patch->on, NSEventMaskKeyDown, ^NSEvent *(NSEvent *event) {
        if (!DPExtensionsShortcut.on || !DPShortcutMatches(event, &DPExtensionsShortcut)) return event;
        NSWindow *window = event.window;
        id browser = window ? [DPBrowsers objectForKey:window] : nil;
        if (!browser) return event;
        if (!event.isARepeat) dispatch_async(dispatch_get_main_queue(), ^{ DPShowExtensions(window, browser); });
        return nil;
    });
}

static void DPInstallExtensionsShortcut(void) {
    DPBrowsers = [NSMapTable weakToWeakObjectsMapTable];
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    DPApplyExtensionsShortcut(&DPExtensionsShortcut);
}

DP_PATCH(DPExtensionsShortcut) {
    .key = @"extensionsShortcut",
    .order = 63,
    .title = @"Extensions Shortcut",
    .detail = @"Press a shortcut, ⇧⌘X unless you set another, for a menu of your extensions. Choosing one opens it as its toolbar button would.",
    .symbol = @"puzzlepiece.extension.fill puzzlepiece.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaBrowser),
    .install = DPInstallExtensionsShortcut,
    .apply = DPApplyExtensionsShortcut,
    .shortcut = @"extensionsMenuShortcut",
    .defaultShortcut = DPDefaultExtensionsShortcut,
};
