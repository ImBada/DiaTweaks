#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

extern DPPatch DPPinnedSplitClose;

static void DPGatherViews(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPGatherViews(sub, cls, out);
}

static NSArray<NSView *> *DPViewsIn(NSView *root, const char *className) {
    Class cls = className ? objc_getClass(className) : Nil;
    NSMutableArray<NSView *> *out = [NSMutableArray array];
    if (cls && root) DPGatherViews(root, cls, out);
    return out;
}

static NSUInteger DPCountViews(NSView *view, Class cls) {
    NSUInteger count = [view isKindOfClass:cls] ? 1 : 0;
    for (NSView *sub in view.subviews) count += DPCountViews(sub, cls);
    return count;
}

static id DPObjectIvar(id object, const char *name) {
    void **slot = DPIvar(object, name);
    return slot ? (__bridge id)*slot : nil;
}

// A Swift Dictionary or Array keeps its count at +16 of its storage and the empty singleton reports 0 there, so empty never reads as a split.
static NSUInteger DPStoredCount(id object, const char *name) {
    void **slot = DPIvar(object, name);
    uintptr_t storage = slot ? (uintptr_t)*slot : 0;
    if (!storage) return 0;
    long count = *(long *)(storage + 16);
    return count > 0 && count < 1024 ? (NSUInteger)count : 0;
}

// A multi-payload enum with a 16-byte payload keeps the payload first and its tag last, so the first 16 bytes are the UUID in every case.
static NSString *DPUUIDIvar(id object, const char *name) {
    uint8_t *bytes = DPIvar(object, name);
    if (!bytes) return nil;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]];
}

static BOOL DPPaneIsPinned(NSView *pane) {
    __attribute__((objc_precise_lifetime)) id attributes = DPAttributes(pane);
    BOOL *pinned = DPIvar(attributes, "isInFavoritesOrPinnedContainer");
    return pinned && *pinned;
}

static NSString *DPPaneTabID(NSView *pane) { return DPUUIDIvar(DPViewModelDelegate(pane), "tabID"); }

static BOOL DPSameID(NSString *one, NSString *other) {
    return one && other && [one caseInsensitiveCompare:other] == NSOrderedSame;
}

static BOOL DPPaneIsSplit(NSView *pane) {
    NSView *tab = DPEnclosingTab(pane);
    Class content = tab ? objc_getClass(DPDiaTabContentView) : Nil;
    return content && DPCountViews(tab, content) > 1;
}

// Rows and top tabs hold one TabContentView per pane, tiles one controller per pane; only the item holding the front tab is what ⌘W means.
static NSView *DPFocusedPinnedSplit(NSWindow *window) {
    if (!window) return nil;
    NSString *active = DPActiveTabID(window);
    NSView *onlyRow = nil, *onlyTile = nil;
    NSUInteger rows = 0, tiles = 0;
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        if (tab.window != window || tab.isHiddenOrHasHiddenAncestor) continue;
        NSArray<NSView *> *panes = DPViewsIn(tab, DPDiaTabContentView);
        if (panes.count < 2) continue;
        BOOL pinned = NO, focused = DPSameID(DPUUIDIvar(DPViewModelDelegate(tab), "tabID"), active);
        for (NSView *pane in panes) {
            if (DPPaneIsPinned(pane)) pinned = YES;
            if (DPSameID(DPPaneTabID(pane), active)) focused = YES;
        }
        if (!pinned) continue;
        if (focused) return tab;
        rows++;
        onlyRow = tab;
    }
    for (NSView *tile in DPFindViews(DPDiaPinnedTab)) {
        if (tile.window != window || tile.isHiddenOrHasHiddenAncestor) continue;
        id controller = DPViewModelDelegate(tile);
        if (DPStoredCount(controller, "contentControllers") < 2) continue;
        // A folder's itemID carries a group UUID, which is never a tab's.
        if ([[[DPSwiftValue(controller, @"itemID") description] lowercaseString] containsString:@"group"]) continue;
        if (DPSameID(DPUUIDIvar(controller, "itemID"), active)) return tile;
        tiles++;
        onlyTile = tile;
    }
    if (active) return nil;
    if (rows == 1 && !tiles) return onlyRow;
    return tiles == 1 && !rows ? onlyTile : nil;
}

// Right-clicking a pinned or favorite Split View and choosing Close unloads it in place, keeping both panes.
static BOOL DPCloseItem(NSView *item) {
    NSMenu *menu = DPTabContextMenu(item);
    NSMenuItem *close = [menu itemWithTitle:@"Close"];
    if (!close || close.hidden || !close.enabled) return NO;
    [menu performActionForItemAtIndex:[menu indexOfItem:close]];
    return YES;
}

static BOOL DPOverlayOnTop(NSWindow *window) {
    if (window.attachedSheet) return YES;
    Class overlay = NSClassFromString(@"DPCommandBarOverlay");
    if (overlay)
        for (NSView *sub in window.contentView.subviews)
            if ([sub isKindOfClass:overlay] && !sub.isHiddenOrHasHiddenAncestor) return YES;
    Class card = NSClassFromString(@"DPPeekCard");
    return card && DPFindView(window.contentView, ^BOOL(NSView *view) {
        return [view isKindOfClass:card] && !view.isHiddenOrHasHiddenAncestor;
    }) != nil;
}

static void DPWindowController_closeFocusedContent(id self, SEL _cmd, id sender) {
    if (DPPinnedSplitClose.on) {
        NSWindow *window = DPValueForKey(self, @"window");
        if (window && window == NSApp.keyWindow && !DPOverlayOnTop(window)) {
            NSView *item = DPFocusedPinnedSplit(window);
            if (item && DPCloseItem(item)) return;
        }
    }
    DPCallOriginal(DPWindowController_closeFocusedContent, self, sender);
}

static char DPOriginalIconKey;

static NSImageView *DPIconView(NSView *content) {
    id standard = DPObjectIvar(content, "$__lazy_storage_$_standardIconView");
    if ([standard isKindOfClass:NSImageView.class]) return standard;
    static const char *const containers[] = {"$__lazy_storage_$_iconView", "$__lazy_storage_$_iconContainerView"};
    for (size_t i = 0; i < sizeof containers / sizeof *containers; i++) {
        NSView *container = DPObjectIvar(content, containers[i]);
        NSImageView *found = (NSImageView *)DPFindView(container, ^BOOL(NSView *view) { return [view isKindOfClass:NSImageView.class]; });
        if (found) return found;
    }
    return nil;
}

static NSImage *DPSplitIcon(void) {
    static NSImage *icon;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
        icon = [[NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:nil] imageWithSymbolConfiguration:config];
    });
    return icon;
}

// Dia leaves a Split View's icon slot empty and may hide it, so both are recorded and only what this tweak changed is put back.
static void DPShowSplitIcon(NSView *content, BOOL on) {
    NSImageView *icon = DPIconView(content);
    if (!icon) return;
    NSMutableDictionary *original = DPGet(icon, &DPOriginalIconKey);
    if (on) {
        if (!original) {
            if (icon.image) return;
            original = [NSMutableDictionary dictionaryWithObject:NSNull.null forKey:@"image"];
            DPSet(icon, &DPOriginalIconKey, original);
        }
        if (!icon.image) icon.image = DPSplitIcon();
        if (icon.hidden) {
            if (!original[@"hidden"]) original[@"hidden"] = @YES;
            icon.hidden = NO;
        }
        return;
    }
    if (![original isKindOfClass:NSMutableDictionary.class]) return;
    if (icon.image == DPSplitIcon()) icon.image = original[@"image"] == NSNull.null ? nil : original[@"image"];
    if (original[@"hidden"]) icon.hidden = [original[@"hidden"] boolValue];
    DPSet(icon, &DPOriginalIconKey, nil);
}

static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    if (!DPPinnedSplitClose.on || !DPPaneIsPinned(self) || !DPPaneIsSplit(self)) return;
    DPShowSplitIcon(self, YES);
}

static NSArray<NSView *> *DPAllContents(void) {
    Class cls = objc_getClass(DPDiaTabContentView);
    NSMutableArray<NSView *> *out = [NSMutableArray array];
    if (!cls) return out;
    for (NSWindow *window in NSApp.windows) DPGatherViews(window.contentView, cls, out);
    return out;
}

static void DPApplyPinnedSplitClose(DPPatch *patch) {
    if (!patch->on) for (NSView *content in DPAllContents()) DPShowSplitIcon(content, NO);
    DPRelayoutTabContents();
}

static NSString *DPVerifyPinnedSplitClose(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaWindowController), @selector(closeFocusedContent:), (IMP)DPWindowController_closeFocusedContent))
        return @"⌘W does not reach the tweak";
    if (!DPIsHooked(objc_getClass(DPDiaTabContentView), @selector(layout), (IMP)DPContent_layout))
        return @"tab content layout does not reach the tweak";
    for (NSView *content in DPFindViews(DPDiaTabContentView)) {
        if (content.needsLayout || !DPPaneIsPinned(content) || !DPPaneIsSplit(content)) continue;
        NSImageView *icon = DPIconView(content);
        if (!icon) continue;
        if (patch->on && !icon.image) return @"a pinned split pane has no icon";
        if (!patch->on && DPGet(icon, &DPOriginalIconKey)) return @"a pinned split pane still shows the split icon";
    }
    return nil;
}

static void DPInstallPinnedSplitClose(void) {
    DPHook(DPDiaWindowController, @selector(closeFocusedContent:), (IMP)DPWindowController_closeFocusedContent);
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
}

DP_PATCH(DPPinnedSplitClose) {
    .key = @"pinnedSplitClose",
    .order = 83,
    .section = @"Sidebar & Tab Bar",
    .group = @"pinnedTabs",
    .title = @"Unload Pinned Splits",
    .detail = @"Press ⌘W on a pinned or favorite Split View to unload it in place, keeping both panes, as right-clicking it and choosing Close does. Pinned splits also get a split icon so you can tell them apart.",
    .symbol = @"rectangle.split.2x1",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaWindowController, DPDiaTabView, DPDiaTabContentView, DPDiaPinnedTab),
    .install = DPInstallPinnedSplitClose,
    .apply = DPApplyPinnedSplitClose,
    .verify = DPVerifyPinnedSplitClose,
};
