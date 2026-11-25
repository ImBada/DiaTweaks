#import "AppIcon.h"
#import <objc/message.h>

static NSUInteger DPHandbacks;
static BOOL DPSettingDockIcon, DPDrawsOwnTile;
static NSString *const DPOwnTileKey = @"appIconOwnTile";

// 0-2 default, 3-5 clear (3 auto, 5 dark), 6-8 tinted.
static unsigned DPIconStyle(void) {
    static Class configuration;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ configuration = NSClassFromString(@"SLSIconAppearanceConfiguration"); });
    SEL fetch = NSSelectorFromString(@"fetchCurrentIconAppearanceConfiguration"), theme = NSSelectorFromString(@"iconAppearanceTheme");
    id current = [configuration respondsToSelector:fetch] ? ((id (*)(id, SEL))objc_msgSend)(configuration, fetch) : nil;
    return [current respondsToSelector:theme] ? ((unsigned (*)(id, SEL))objc_msgSend)(current, theme) : 1;
}

static void DPSetTileImage(NSImage *image) {
    DPSettingDockIcon = YES;
    NSApp.applicationIconImage = image;
    if (!image) {
        NSApp.dockTile.contentView = nil;
        [NSApp.dockTile display];
    }
    DPSettingDockIcon = NO;
}

static void DPDrawTile(void) {
    NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:NSBundle.mainBundle.bundlePath];
    icon.size = NSMakeSize(512, 512);
    unsigned style = DPIconStyle();
    BOOL dark = style == 5 || (style == 3 && [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] == NSAppearanceNameDarkAqua);
    DPSetTileImage(style >= 3 && style <= 5 ? DPClearTile(icon, dark) : icon);
}

static void DPIconStyleDidChange(NSNotification *note) {
    if (!DPDrawsOwnTile) return;
    DPDrawTile();
    NSUInteger current = ++DPHandbacks;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 500), dispatch_get_main_queue(), ^{
        if (current != DPHandbacks || !DPDrawsOwnTile) return;
        DPDrawsOwnTile = NO;
        [DPSettingsDefaults() removeObjectForKey:DPOwnTileKey];
        DPSetTileImage(nil);
    });
}

void DPDrawOwnTile(void) {
    DPDrawsOwnTile = YES;
    [DPSettingsDefaults() setBool:YES forKey:DPOwnTileKey];
    DPDrawTile();
}

BOOL DPOwnTileInDock(void) { return [DPSettingsDefaults() boolForKey:DPOwnTileKey]; }

static void DPDockTile_setContentView(NSDockTile *self, SEL _cmd, NSView *view) {
    if (!DPAppIcon.on || DPSettingDockIcon) DPCallOriginal(DPDockTile_setContentView, self, view);
}

void DPInstallDockTile(void) {
    DPHook("NSDockTile", @selector(setContentView:), (IMP)DPDockTile_setContentView);
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:@"NSWorkspaceIconAppearanceConfigurationDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPIconStyleDidChange(note); }];
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"AppleInterfaceThemeChangedNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPIconStyleDidChange(note); }];
}
