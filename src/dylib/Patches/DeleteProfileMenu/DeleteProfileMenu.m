#import "Patches/DeleteProfileMenu/DeleteProfileMenu.h"
#import "Patches/CommandBar/Tabs.h"

static NSString *const DPEditProfile = @"Edit Profile…", *const DPDeleteTitle = @"Delete Profile…";

// The window's profiles, or nil in a private window.
NSArray *DPProfilesOf(NSWindow *window) {
    id profiles = DPValueForKey(DPScriptWindow(window), @"appleScriptProfiles");
    return [profiles isKindOfClass:NSArray.class] ? profiles : nil;
}

static char DPOursKey;

// The window's active profile's name and place, or no when Dia wouldn't offer a delete: its last profile, or one already running.
static BOOL DPDeleteWanted(NSWindow *window, NSMenu *edit, NSString **name, NSUInteger *index) {
    NSArray *profiles = DPProfilesOf(window);
    id active = DPValueForKey(DPScriptWindow(window), @"activeProfile");
    NSString *profileName = [DPValueForKey(active, @"name") description];
    id oneBased = DPValueForKey(active, @"orderedIndex");  // Scripting hands out a new object each time, so ask it.
    NSUInteger place = [oneBased respondsToSelector:@selector(integerValue)] && [oneBased integerValue] > 0 ? [oneBased integerValue] - 1 : NSNotFound;
    if (name) *name = profileName;
    if (index) *index = place;
    // Dia won't delete a window's last profile, and one delete runs at a time.
    return DPDeleteProfileMenu.on && [edit itemWithTitle:@"Profile Settings"] != nil && profiles.count > 1
        && profileName.length > 0 && place != NSNotFound && !DPDeletingProfile();
}

static void DPPurgeDeleteItem(NSMenu *menu) {
    NSMenu *edit = [menu itemWithTitle:DPEditProfile].submenu;
    for (NSMenuItem *item in [edit.itemArray copy]) if (DPGet(item, &DPOursKey)) [edit removeItem:item];
}

// Puts a fresh Delete Profile… for the window's current profile in Edit Profile, replacing one from an
// earlier right-click if Dia reuses the menu.
static void DPAddDeleteItem(NSMenu *menu, NSWindow *window) {
    DPPurgeDeleteItem(menu);
    if (!DPDeleteProfileMenu.on) return;  // Off, so leave Dia's menu as it is and never ask Dia about profiles.
    NSMenu *edit = [menu itemWithTitle:DPEditProfile].submenu;
    NSString *name = nil;
    NSUInteger index = 0;
    if (!DPDeleteWanted(window, edit, &name, &index)) return;
    __weak NSWindow *weakWindow = window;
    NSMenuItem *item = DPMenuItem(DPDeleteTitle, ^{
        NSMenuItem *settings = [edit itemWithTitle:@"Profile Settings"];
        if (DPDeleteProfileMenu.on && weakWindow && settings) DPDeleteProfile(weakWindow, name, index, settings);
    });
    DPSet(item, &DPOursKey, @YES);
    [edit insertItem:item atIndex:[edit indexOfItem:[edit itemWithTitle:@"Profile Settings"]] + 1];
}

static NSMenu *DPSidebarRoot_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPSidebarRoot_menuForEvent, self, event);
    DPAddDeleteItem(menu, self.window);
    return menu;
}

// The sidebar's header and footer, and Sidebar Grain, get the same menu from here.
static NSMenu *DPSidebarContainer_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPSidebarContainer_menuForEvent, self, event);
    DPAddDeleteItem(menu, self.window);
    return menu;
}

static NSMenu *DPTabStrip_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPTabStrip_menuForEvent, self, event);
    DPAddDeleteItem(menu, self.window);
    return menu;
}

static void DPInstallDeleteProfileMenu(void) {
    DPHook(DPDiaSidebarRoot, @selector(menuForEvent:), (IMP)DPSidebarRoot_menuForEvent);
    DPHook(DPDiaSidebarContainerRoot, @selector(menuForEvent:), (IMP)DPSidebarContainer_menuForEvent);
    DPHook(DPDiaTabStripTabs, @selector(menuForEvent:), (IMP)DPTabStrip_menuForEvent);
    DPInstallSettingsHooks();
    DPOnQuit(^{ DPFinishProfileDelete(YES); });  // Never leave Settings hidden or a delete stuck on the way out.
}

static void DPApplyDeleteProfileMenu(DPPatch *patch) {
    if (patch->on) return;
    DPEndProfileDelete();
    // Dia hands back a menu it keeps, so take our item out of those too. Asking it for a new one would read its profiles.
    for (NSString *cls in @[ @DPDiaSidebarRoot, @DPDiaSidebarContainerRoot, @DPDiaTabStripTabs ])
        for (NSView *view in DPFindViews(cls.UTF8String)) DPPurgeDeleteItem(view.menu);
}

// Asks the sidebar or tab bar for its right-click menu, as a right-click would.
static NSString *DPVerifyDeleteProfileMenu(DPPatch *patch) {
    BOOL asked = NO, sawEdit = NO;
    for (NSString *cls in @[ @DPDiaSidebarRoot, @DPDiaSidebarContainerRoot, @DPDiaTabStripTabs ])
        for (NSView *view in DPFindViews(cls.UTF8String)) {
            if (view.hiddenOrHasHiddenAncestor || !view.window.isVisible || !DPProfilesOf(view.window)) continue;
            NSPoint point = [view convertPoint:NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView:nil];
            NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0
                windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            NSMenu *edit = [[view menuForEvent:event] itemWithTitle:DPEditProfile].submenu;
            asked = YES;
            if (!edit) continue;
            sawEdit = YES;
            BOOL want = patch->on && DPDeleteWanted(view.window, edit, NULL, NULL), has = [edit itemWithTitle:DPDeleteTitle] != nil;
            if (want != has) return want ? @"Edit Profile has no Delete Profile" : @"Edit Profile still has Delete Profile";
        }
    if (patch->on && asked && !sawEdit) return @"the right-click menu has no Edit Profile";
    return nil;
}

DP_PATCH(DPDeleteProfileMenu) {
    .key = @"deleteProfileMenu",
    .order = 85,
    .title = @"Delete Profile from Sidebar",
    .detail = @"Add Delete Profile… to Edit Profile when you right-click the sidebar or tab bar. Dia still asks you to type the profile’s name first.",
    .symbol = @"trash",
    .tint = @"systemRedColor",
    .section = @"Profiles",
    .experimental = YES,
    .classes = DPClasses(DPDiaSidebarRoot, DPDiaSidebarContainerRoot, DPDiaTabStripTabs, DPDiaSettingsWindow, DPDiaProfilesTable, DPDiaDialogPanelWC),
    .install = DPInstallDeleteProfileMenu,
    .apply = DPApplyDeleteProfileMenu,
    .verify = DPVerifyDeleteProfileMenu,
};
