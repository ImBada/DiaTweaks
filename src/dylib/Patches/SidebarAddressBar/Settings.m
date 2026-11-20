#import "Settings.h"

void DPSidebarResetOptions(NSUserDefaults *settings) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *option = DPPatches[i];
        if (![option->requires isEqualToString:@"sidebarAddressBar"]) continue;
        [settings setBool:option->defaultOn forKey:option->key];
        DPSetPatch(option, option->defaultOn && !option->unavailable, NO);
    }
    [settings synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

@interface DPSidebarResetButton : NSButton @end
@implementation DPSidebarResetButton
- (void)resetOptions:(id)sender {
    DPSidebarResetOptions([[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]);
}
@end

NSArray<NSView *> *DPSidebarSettingsRows(void) {
    DPSidebarResetButton *button = [DPSidebarResetButton new];
    button.title = @"Reset options to defaults";
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:12];
    button.target = button;
    button.action = @selector(resetOptions:);
    button.toolTip = @"Reset only Sidebar address bar options. Keep this patch and other patches as they are.";
    NSStackView *row = [NSStackView stackViewWithViews:@[button]];
    row.alignment = NSLayoutAttributeLeading;
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    return @[row];
}
