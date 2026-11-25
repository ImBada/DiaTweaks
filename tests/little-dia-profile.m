#import "Patches/LittleDia/Profile.m"

static int failures;

@interface CountingMenuDelegate : NSObject <NSMenuDelegate>
@property NSInteger updates;
@end
@implementation CountingMenuDelegate
- (void)menuNeedsUpdate:(NSMenu *)menu { self.updates++; }
@end

static void check(BOOL ok, const char *what) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

static void label(NSString *what, NSString *profile, NSUInteger profiles, NSString *want) {
    NSString *got = DPOpenInLabel(profile, profiles);
    if (![got isEqual:want]) printf("FAIL %s: \"%s\", want \"%s\"\n", what.UTF8String, got.UTF8String, want.UTF8String), failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        label(@"one profile", @"Personal", 1, @"Open in Dia");
        label(@"no profiles known", @"Personal", 0, @"Open in Dia");
        label(@"two profiles", @"Personal", 2, @"Open in Personal");
        label(@"many profiles", @"Work", 5, @"Open in Work");
        label(@"name not known yet", nil, 2, @"Open in Dia");
        label(@"empty name", @"", 2, @"Open in Dia");
        label(@"name of spaces", @"  ", 2, @"Open in Dia");
        label(@"name of Braille's blank cell", @"\u2800", 3, @"Open in Dia");
        label(@"padded name", @" Work\u2800", 2, @"Open in Work");

        NSArray<NSString *> *names = @[ @"Personal", @"Work", @"Study", @"Travel" ];
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        NSMenu *moveMenu = [[NSMenu alloc] initWithTitle:@"Move to Profile"];
        for (NSString *n in names) {
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:n action:nil keyEquivalent:@""];
            it.image = img;
            [moveMenu addItem:it];
        }
        CountingMenuDelegate *moveDel = [CountingMenuDelegate new];
        moveMenu.delegate = moveDel;

        NSMenu *tabsMenu = [[NSMenu alloc] initWithTitle:@"Tabs"];
        NSMenuItem *moveRoot = [[NSMenuItem alloc] initWithTitle:@"Move to Profile" action:nil keyEquivalent:@""];
        moveRoot.submenu = moveMenu;
        [tabsMenu addItem:moveRoot];
        CountingMenuDelegate *tabsDel = [CountingMenuDelegate new];
        tabsMenu.delegate = tabsDel;

        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *tabsRoot = [[NSMenuItem alloc] initWithTitle:@"Tabs" action:nil keyEquivalent:@""];
        tabsRoot.submenu = tabsMenu;
        [mainMenu addItem:tabsRoot];
        NSApp.mainMenu = mainMenu;

        for (NSString *n in names) check(DPLittleDiaProfileImage(n) == img, "DPLittleDiaProfileImage finds every profile image");
        check(tabsDel.updates == 1 && moveDel.updates == 1, "DPLittleDiaProfileImage updates Tabs and Move to Profile once per turn across all profiles");
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        check(DPLittleDiaProfileImage(@"Personal") == img && tabsDel.updates == 2 && moveDel.updates == 2,
              "next run-loop turn refreshes the profile submenu again");
    }
    if (failures) return 1;
    puts("PASS: the Open button names the profile only when there are several");
    return 0;
}
