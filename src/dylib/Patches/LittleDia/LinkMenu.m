#import "LittleDia.h"

static char DPItemKey;
static NSURL *gLink;
static NSDate *gLinkAt;
static NSHashTable<NSMenu *> *DPTaggedMenus;

static NSString *const DPItemTitle = @"Open Link in Little Dia";

static BOOL DPIsOpenLinkItem(NSMenuItem *item) {
    return [item.title rangeOfString:@"Open Link" options:NSCaseInsensitiveSearch | NSAnchoredSearch].location != NSNotFound;
}

static BOOL DPPage_willShowMenu(id self, SEL _cmd, id page, id menu, id element) {
    if (!DPLittleDia.on) {
        gLink = nil;
        return DPCallOriginal(DPPage_willShowMenu, self, page, menu, element);
    }
    NSURL *url = DPValueForKey(element, @"linkURL");
    NSString *scheme = [url isKindOfClass:NSURL.class] ? url.scheme : nil;
    BOOL web = scheme && ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame);
    gLink = web ? url : nil;
    gLinkAt = NSDate.date;
    return DPCallOriginal(DPPage_willShowMenu, self, page, menu, element);
}

static BOOL DPIsWebLinkMenu(NSMenu *menu, NSView *view) {
    if (!view || DPIsKind(view, "RenderWidgetHostViewCocoa") || DPIsKind(view, "WebContentsViewCocoa")) return YES;
    for (NSMenuItem *item in menu.itemArray)
        if (DPIsOpenLinkItem(item)) return YES;
    return NO;
}

static void DPAddLinkItem(NSMenu *menu, NSView *view) {
    BOOL tagged = DPTaggedMenus.count && [DPTaggedMenus containsObject:menu];
    if (!gLink && !tagged) return;
    if (tagged) {
        for (NSMenuItem *old in menu.itemArray)
            if (DPGet(old, &DPItemKey)) [menu removeItem:old];
        [DPTaggedMenus removeObject:menu];
    }
    if (!gLink || !DPIsWebLinkMenu(menu, view)) return;
    NSURL *url = gLink;
    BOOL fresh = gLinkAt.timeIntervalSinceNow > -2;
    gLink = nil;
    if (!url || !fresh || !DPLittleDia.on || !DPLittleDiaReady()) return;
    NSMenuItem *item = DPMenuItem(DPItemTitle, ^{ DPOpenLinkInLittleDia(url); });
    DPSet(item, &DPItemKey, @YES);
    NSInteger at = 0;
    NSArray<NSMenuItem *> *items = menu.itemArray;
    for (NSUInteger i = 0; i < items.count; i++)
        if (DPIsOpenLinkItem(items[i])) at = (NSInteger)i + 1;
    [menu insertItem:item atIndex:at];
    [DPTaggedMenus addObject:menu];
}

static void DPMenu_popUpContext(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view) {
    DPAddLinkItem(menu, view);
    DPCallOriginal(DPMenu_popUpContext, self, menu, event, view);
}

static void DPMenu_popUpContextFont(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view, NSFont *font) {
    DPAddLinkItem(menu, view);
    DPCallOriginal(DPMenu_popUpContextFont, self, menu, event, view, font);
}

static BOOL DPMenu_popUpAt(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    DPAddLinkItem(self, view);
    return DPCallOriginal(DPMenu_popUpAt, self, item, location, view);
}

void DPInstallLittleDiaLinkMenu(void) {
    DPTaggedMenus = [NSHashTable weakObjectsHashTable];
    Class menus = object_getClass(NSMenu.class);
    DPHookClass(menus, @selector(popUpContextMenu:withEvent:forView:), (IMP)DPMenu_popUpContext);
    DPHookClass(menus, @selector(popUpContextMenu:withEvent:forView:withFont:), (IMP)DPMenu_popUpContextFont);
    DPHookClass(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPMenu_popUpAt);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:willShowContextMenu:withElement:), (IMP)DPPage_willShowMenu);
    });
}

NSString *DPLittleDiaLinkMenuProblem(void) {
    Class page = objc_getClass(DPDiaWebContent);
    if (!DPIsHooked(page, @selector(webContents:willShowContextMenu:withElement:), (IMP)DPPage_willShowMenu))
        return @"link menus don't reach Little Dia";
    return nil;
}
