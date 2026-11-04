#import "NativeControls.h"

static char DPSidebarMenuStyleKey;
static __weak DPSidebarAddressRow *DPTrackingSiteMenu;
static __weak DPSidebarAddressRow *DPPageActionRow;
static __weak NSView *DPPageActionSource;

static NSView *DPPageActionAnchor(NSView *source) {
    DPSidebarAddressRow *row = DPPageActionRow;
    NSView *control = DPPageActionSource;
    if (!row.window || !control) return nil;
    NSView *toolbar = DPAddressControlsFor(row,NO).toolbar;
    if (source && (source.window != row.window ||
        (![source isDescendantOf:toolbar] && ![control isDescendantOf:source]))) return nil;
    return row;
}

static NSString *const DPPageMenuPrefix = @"DiaTweaks.SidebarAddressBar.Page.";

static NSArray<NSArray<NSString *> *> *DPPageMenuLabels(void) {
    return @[@[@"Bookmark this page",@"Edit bookmark",@"Remove bookmark",@"Add Bookmark…"],
             @[@"Split tabs",@"Exit split",@"Split Tab",@"Open Split Pane"],
             @[@"Chat with this tab"],
             @[@"Included in AI history search",@"Excluded from AI history search"]];
}

static NSView *DPPageControl(DPSidebarAddressRow *row, NSArray<NSString *> *labels) {
    return DPFindView(DPAddressControlsFor(row,NO).toolbar, ^BOOL(NSView *view) {
        return view.accessibilityLabel && [labels containsObject:view.accessibilityLabel];
    });
}

static NSMenuItem *DPPageMenuCommand(NSMenu *menu, NSArray<NSString *> *labels) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([labels containsObject:item.title] && item.action) return item;
        NSMenuItem *nested = DPPageMenuCommand(item.submenu,labels);
        if (nested) return nested;
    }
    return nil;
}

@implementation DPSidebarAddressRow (SiteMenu)
- (void)performNativePageAction:(NSMenuItem *)sender {
    NSArray<NSString *> *labels = sender.representedObject;
    NSWindow *window = self.window;
    NSString *url = DPSidebarURL(window);
    // The native Chat panel must open after AppKit has ended menu tracking.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!window || self.window != window || ![(DPSidebarURL(window) ?: @"") isEqual:(url ?: @"")]) return;
        [self invokeNativePageAction:labels];
    });
}
- (void)invokeNativePageAction:(NSArray<NSString *> *)labels {
    NSView *view = DPPageControl(self,labels);
    NSMenuItem *command = DPPageMenuCommand(NSApp.mainMenu,labels);
    DPSidebarAddressRow *previousRow = DPPageActionRow;
    NSView *previousSource = DPPageActionSource;
    DPPageActionRow = self;
    DPPageActionSource = view;
    BOOL isChat = [labels containsObject:@"Chat with this tab"];
    NSMenuItem *chatCommand = isChat ? DPPageMenuCommand(NSApp.mainMenu,@[@"Chat…"]) : nil;
    BOOL wasHidden = view.hidden;
    @try {
        // Use the native File command when the toolbar’s Chat control is hidden.
        if (isChat && (!view || view.hiddenOrHasHiddenAncestor || DPAddressControlsFor(self,NO).toolbar.alphaValue == 0)
            && chatCommand.enabled && [NSApp sendAction:chatCommand.action to:chatCommand.target from:chatCommand]) return;
        // Chat can be hidden by a toolbar preference. Its native press needs a visible control.
        if (wasHidden && isChat) view.hidden = NO;
        if ([view isKindOfClass:NSControl.class]) {
            NSControl *control = (NSControl *)view;
            if (control.action && [NSApp sendAction:control.action to:control.target from:control]) return;
        }
        if ([view accessibilityPerformPress]) return;
        if (command.enabled && [NSApp sendAction:command.action to:command.target from:command]) return;
        if (chatCommand.enabled && [NSApp sendAction:chatCommand.action to:chatCommand.target from:chatCommand]) return;
        NSBeep();
    } @finally {
        if (view.hidden != wasHidden && isChat) view.hidden = wasHidden;
        DPPageActionRow = previousRow;
        DPPageActionSource = previousSource;
    }
}
@end

static void DPAddressStyleMenuItem(NSMenuItem *item) {
    if (item.separatorItem) return;
    NSString *title = (item.attributedTitle.string ?: item.title).lowercaseString;
    if ([title hasPrefix:@"paste and go"] || [title hasPrefix:@"paste & go"] ||
        [title hasPrefix:@"paste and search"] || [title hasPrefix:@"paste & search"]) {
        NSString *compactTitle = [title containsString:@"search"] && ![title hasPrefix:@"paste and go"]
            && ![title hasPrefix:@"paste & go"] ? @"Paste and Search…" : @"Paste and Go…";
        if (item.attributedTitle) item.attributedTitle = nil;
        if (![item.title isEqual:compactTitle]) item.title = compactTitle;
    }
    if (item.image) return;
    NSAttributedString *original = item.attributedTitle;
    if (original.length && [original attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL]) return;
    NSString *symbol = nil;
    if ([title hasPrefix:@"share"]) symbol = @"square.and.arrow.up";
    else if ([title hasPrefix:@"copy link"] || [title hasPrefix:@"copy url"]) symbol = @"link";
    else if ([title containsString:@"bookmark"]) symbol = @"bookmark";
    else if ([title containsString:@"split"]) symbol = @"rectangle.split.2x1";
    else if ([title hasPrefix:@"chat with this tab"]) symbol = @"bubble.left";
    else if ([title containsString:@"ai history search"]) symbol = @"clock.arrow.circlepath";
    else if ([title hasPrefix:@"site settings"]) symbol = @"gearshape";
    if (!symbol) return;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    image = [[image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular]] copy];
    if (!image) return;
    image.template = YES;
    // Some of Dia's context menus omit AppKit's optional image column.
    // Put the glyph in the displayed title so it survives that presentation.
    NSTextAttachment *glyph = [NSTextAttachment new];
    glyph.image = image;
    glyph.bounds = NSMakeRect(0, -2, 15, 15);
    NSMutableAttributedString *label = [[NSAttributedString attributedStringWithAttachment:glyph] mutableCopy];
    [label appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
    [label appendAttributedString:original.length ? original : [[NSAttributedString alloc] initWithString:item.title]];
    item.attributedTitle = label;
}

static void DPSidebarMenuUpdate(NSMenu *menu, SEL _cmd) {
    DPCallOriginal(DPSidebarMenuUpdate, menu);
    if (!DPSidebarAddressBar.on || !DPGet(menu, &DPSidebarMenuStyleKey)) return;
    for (NSMenuItem *item in menu.itemArray) DPAddressStyleMenuItem(item);
}

void DPAddressAddPageMenuItems(NSMenu *menu, DPSidebarAddressRow *row, NSInteger index) {
    if (!menu || !row) return;
    DPHookClass(NSMenu.class, @selector(update), (IMP)DPSidebarMenuUpdate);
    DPSet(menu, &DPSidebarMenuStyleKey, @YES);
    for (NSMenuItem *item in menu.itemArray)
        if ([item.identifier hasPrefix:DPPageMenuPrefix]) [menu removeItem:item];
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray new];
    for (NSArray<NSString *> *labels in DPPageMenuLabels()) {
        NSView *view = DPPageControl(row,labels);
        NSMenuItem *command = DPPageMenuCommand(NSApp.mainMenu,labels);
        NSString *title = view.accessibilityLabel ?: command.title;
        if (!title.length || [menu itemWithTitle:title]) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(performNativePageAction:) keyEquivalent:@""];
        item.target = row;
        item.representedObject = labels;
        if ([title isEqual:@"Included in AI history search"]) item.state = NSControlStateValueOn;
        item.identifier = [DPPageMenuPrefix stringByAppendingString:title];
        [items addObject:item];
    }
    for (NSMenuItem *item in menu.itemArray) DPAddressStyleMenuItem(item);
    for (NSMenuItem *item in items) DPAddressStyleMenuItem(item);
    if (!items.count) return;
    index = MIN(index,menu.numberOfItems);
    if (index && ![menu itemAtIndex:index-1].separatorItem) {
        NSMenuItem *separator = NSMenuItem.separatorItem;
        separator.identifier = [DPPageMenuPrefix stringByAppendingString:@"leading"];
        [menu insertItem:separator atIndex:index++];
    }
    for (NSMenuItem *item in items) [menu insertItem:item atIndex:index++];
    if (index < menu.numberOfItems && ![menu itemAtIndex:index].separatorItem) {
        NSMenuItem *separator = NSMenuItem.separatorItem;
        separator.identifier = [DPPageMenuPrefix stringByAppendingString:@"trailing"];
        [menu insertItem:separator atIndex:index];
    }
}

static DPSidebarAddressRow *DPAddressSiteMenuOwner(NSView *view) {
    for (; view; view = view.superview) {
        DPAddressNativeSlot *slot = DPAddressNativeSlotFor(view);
        if (slot && DPAddressControlsFor(slot.owner,NO).more == slot) return (DPSidebarAddressRow *)slot.owner;
    }
    return nil;
}

static void DPAddressSiteMenuMouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    DPSidebarAddressRow *previous = DPTrackingSiteMenu;
    DPTrackingSiteMenu = DPAddressSiteMenuOwner(self);
    @try { DPCallOriginal(DPAddressSiteMenuMouseDown,self,event); }
    @finally { DPTrackingSiteMenu = previous; }
}

static void DPAddressPrepareSiteMenu(NSMenu *menu, DPSidebarAddressRow *row) {
    if (!row) return;
    NSInteger index = 0;
    NSMenuItem *existingCopy = nil;
    for (NSMenuItem *entry in menu.itemArray) {
        if ([entry.title hasPrefix:@"Share"] || [entry.title hasPrefix:@"Copy"]) index = [menu indexOfItem:entry] + 1;
        if ([entry.title isEqualToString:@"Copy Link"] || [entry.title isEqualToString:@"Copy URL"]) existingCopy = entry;
    }
    if (row.URLString.length) {
        if (existingCopy) {
            index = [menu indexOfItem:existingCopy];
            [menu removeItem:existingCopy];
        }
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:existingCopy.title ?: @"Copy Link"
                                                   action:@selector(copyLink:) keyEquivalent:existingCopy.keyEquivalent ?: @""];
        if (existingCopy) copy.keyEquivalentModifierMask = existingCopy.keyEquivalentModifierMask;
        copy.target = row;
        copy.identifier = @"DiaTweaks.SidebarAddressBar.Copy";
        [menu insertItem:copy atIndex:index++];
    }
    DPAddressAddPageMenuItems(menu,row,index);
}

static void DPAddressSiteContextPopup(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view) {
    NSView *anchor = DPPageActionAnchor(view);
    if (anchor && event.window == anchor.window) {
        NSPoint point = [anchor convertPoint:NSMakePoint(NSMaxX(anchor.bounds),NSMaxY(anchor.bounds)) toView:nil];
        event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0
                                 timestamp:event.timestamp windowNumber:anchor.window.windowNumber context:nil
                               eventNumber:event.eventNumber clickCount:1 pressure:1];
        view = anchor;
    }
    DPAddressPrepareSiteMenu(menu,DPAddressSiteMenuOwner(view) ?: DPTrackingSiteMenu);
    DPCallOriginal(DPAddressSiteContextPopup,self,menu,event,view);
}

static BOOL DPAddressSiteMenuPopup(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    NSView *anchor = DPPageActionAnchor(view);
    if (anchor) {
        view = anchor;
        location = NSMakePoint(NSMaxX(anchor.bounds),NSMaxY(anchor.bounds));
    }
    DPAddressPrepareSiteMenu(self,DPAddressSiteMenuOwner(view) ?: DPTrackingSiteMenu);
    return DPCallOriginal(DPAddressSiteMenuPopup,self,item,location,view);
}

static void DPAddressPagePopoverShow(NSPopover *self, SEL _cmd, NSRect rect, NSView *source, NSRectEdge edge) {
    NSView *anchor = DPPageActionAnchor(source);
    if (anchor) {
        source = anchor;
        rect = anchor.bounds;
        edge = NSMaxXEdge;
    }
    DPCallOriginal(DPAddressPagePopoverShow,self,rect,source,edge);
}

void DPAddressInstallSiteMenuHooks(NSView *view) {
    DPHookClass(NSPopover.class,@selector(showRelativeToRect:ofView:preferredEdge:),(IMP)DPAddressPagePopoverShow);
    DPHookClass(view.class,@selector(mouseDown:),(IMP)DPAddressSiteMenuMouseDown);
    DPHookClass(object_getClass(NSMenu.class),@selector(popUpContextMenu:withEvent:forView:),(IMP)DPAddressSiteContextPopup);
    DPHookClass(NSMenu.class,@selector(popUpMenuPositioningItem:atLocation:inView:),(IMP)DPAddressSiteMenuPopup);
}
