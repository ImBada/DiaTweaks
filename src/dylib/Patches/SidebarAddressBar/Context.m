#import "NativeControls.h"

static NSHashTable<NSMenu *> *DPTrackingMenus;
static NSTimeInterval DPLastMenuDismissal = -1;

void DPSidebarInstallContextTracking(void) {
    if (DPTrackingMenus) return;
    DPTrackingMenus = [NSHashTable weakObjectsHashTable];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:NSMenu.class]) [DPTrackingMenus addObject:note.object];
    }];
    [center addObserverForName:NSMenuDidEndTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (![DPTrackingMenus containsObject:note.object]) return;
        [DPTrackingMenus removeObject:note.object];
        DPLastMenuDismissal = NSProcessInfo.processInfo.systemUptime;
    }];
}

@implementation DPSidebarAddressRow (Context)
- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (!event || (event.type != NSEventTypeRightMouseDown &&
        !(event.type == NSEventTypeLeftMouseDown && (event.modifierFlags & NSEventModifierFlagControl)))) return nil;
    // AppKit can replay the initiating mouse event when a native context menu closes.
    if (DPTrackingMenus.count || event.timestamp <= DPLastMenuDismissal) return nil;
    if (!self.window || (event.window && event.window != self.window)) return nil;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (![self acceptsAddressMenuAt:point]) return nil;

    NSView *field = DPFindView(self.window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaAddressField) && !view.hidden;
    });
    NSView *site = DPAddressControlsFor(self,NO).more.view;
    NSMenu *native = [site menuForEvent:event] ?: site.menu ?: [field menuForEvent:event];
    // Some versions put the menu on the field's text view instead.
    NSView *text = DPFindView(field, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    if (!native.numberOfItems) native = [text menuForEvent:event];
    // Keep Dia's menu, with explicit address actions that also work while its toolbar field is unfocused.
    // Dia's custom menu items trap in copyWithZone:. Reuse the menu without copying or moving its items.
    NSMenu *menu = native.numberOfItems ? native : [NSMenu new];
    for (NSMenuItem *item in menu.itemArray)
        if ([item.identifier hasPrefix:@"DiaTweaks.SidebarAddressBar."]) [menu removeItem:item];
    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"Edit address…" action:@selector(openEditor:) keyEquivalent:@""];
    edit.target = self;
    edit.identifier = @"DiaTweaks.SidebarAddressBar.Edit";
    [menu insertItem:edit atIndex:0];
    BOOL canCopy = self.URLString.length && ![self.URLString isEqual:@"about:blank"] && ![self.URLString hasPrefix:@"chrome://newtab"];
    if (canCopy) {
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:@"Copy Link" action:@selector(copyLink:) keyEquivalent:@""];
        copy.target = self;
        copy.identifier = @"DiaTweaks.SidebarAddressBar.Copy";
        [menu insertItem:copy atIndex:1];
    }
    if (native) {
        NSMenuItem *separator = NSMenuItem.separatorItem;
        separator.identifier = @"DiaTweaks.SidebarAddressBar.Separator";
        [menu insertItem:separator atIndex:canCopy ? 2 : 1];
    }
    DPAddressAddPageMenuItems(menu,self,canCopy ? 2 : 1);
    return menu;
}
@end
