#import "Startup.h"

static NSMenu *DPAppMenu(void) {
    NSMenu *bar = NSApp.mainMenu;
    return bar.numberOfItems ? [bar itemAtIndex:0].submenu : nil;
}

static NSMenu *DPFileMenu(void) { return [NSApp.mainMenu itemWithTitle:@"File"].submenu; }

static BOOL DPIsSignIn(NSMenuItem *item) {
    return item.menu && item.menu == DPAppMenu() && [item.title hasPrefix:@"Sign In"];
}

static BOOL DPIsLocalAction(NSMenuItem *item) {
    if (!item.menu) return NO;
    static NSSet<NSString *> *appItems, *fileItems;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        appItems = [NSSet setWithArray:@[ @"Settings…", @"Settings...", @"Set as Default Browser", @"Import from Another Browser…", @"Import from Another Browser..." ]];
        fileItems = [NSSet setWithArray:@[ @"New Window", @"New Incognito Window" ]];
    });
    if (item.menu == DPAppMenu()) return [appItems containsObject:item.title];
    return item.menu == DPFileMenu() && [fileItems containsObject:item.title];
}

static void DPApplyItem(NSMenuItem *item) {
    if (DPIsSignIn(item)) item.hidden = YES;
    if (DPIsLocalAction(item)) item.enabled = YES;
}

static void DPItem_setEnabled(NSMenuItem *self, SEL _cmd, BOOL enabled) {
    DPCallOriginal(DPItem_setEnabled, self, enabled || DPIsLocalAction(self));
}

static void DPUpdateMenu(NSMenu *menu) {
    if (menu != DPAppMenu() && menu != DPFileMenu()) return;
    for (NSMenuItem *item in menu.itemArray) DPApplyItem(item);
}

static void DPItem_setHidden(NSMenuItem *self, SEL _cmd, BOOL hidden) {
    DPCallOriginal(DPItem_setHidden, self, hidden || DPIsSignIn(self));
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    DPApplyItem(item);
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    DPApplyItem(item);
}

static void DPMenu_update(NSMenu *self, SEL _cmd) {
    DPCallOriginal(DPMenu_update, self);
    DPUpdateMenu(self);
}

void DPSkipAccountMenus(void) {
    DPHookClass(NSMenuItem.class, @selector(setHidden:), (IMP)DPItem_setHidden);
    DPHookClass(NSMenuItem.class, @selector(setEnabled:), (IMP)DPItem_setEnabled);
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPHookClass(NSMenu.class, @selector(update), (IMP)DPMenu_update);
    DPOnLaunch(^{
        DPUpdateMenu(DPAppMenu());
        DPUpdateMenu(DPFileMenu());
    });
}
