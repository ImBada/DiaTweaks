#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"

static NSString *DPLocalCIdentifier(NSString *name) {
    NSMutableString *identifier = [NSMutableString new];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || (i > 0 && c >= '0' && c <= '9')) [identifier appendFormat:@"%C", c];
    }
    if (!identifier.length) return @"MyTweak";
    if ([identifier characterAtIndex:0] >= '0' && [identifier characterAtIndex:0] <= '9') return [@"Tweak" stringByAppendingString:identifier];
    return identifier;
}

static NSString *DPLocalStarter(NSString *name) {
    NSString *identifier = DPLocalCIdentifier(name);
    NSString *key = [identifier stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[identifier substringToIndex:1].lowercaseString];
    return [NSString stringWithFormat:
        @"#import \"StdPatch/StdPatch.h\"\n"
        @"\n"
        @"// A local tweak is an ordinary DPPatch: it gets a switch in Settings and a key in com.diapatches.\n"
        @"// Change the title, the detail and the body, then relaunch Dia.\n"
        @"DP_PATCH(%@) {\n"
        @"    .key = @\"%@\",\n"
        @"    .defaultOn = NO,\n"
        @"    .title = @\"%@\",\n"
        @"    .detail = @\"What this tweak does, in one line.\",\n"
        @"    .symbol = @\"hammer\",\n"
        @"    .tint = @\"systemOrangeColor\",\n"
        @"    .section = @\"Local\",\n"
        @"};\n",
        identifier, key, name];
}

static void DPLocalAlert(NSString *title, NSString *text) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = text;
    [alert runModal];
}

static NSString *DPLocalStatusText(NSString *status) {
    if ([status isEqual:@"loaded"]) return @"Loaded";
    if ([status isEqual:@"ready"]) return @"Ready — relaunch Dia";
    if ([status isEqual:@"incompatible"]) return @"Incompatible";
    return @"Build failed";
}

static NSString *DPLocalKindText(NSString *kind) {
    if ([kind isEqual:@"patch"]) return @"Patch";
    if ([kind isEqual:@"dylib"]) return @"Dylib";
    if ([kind isEqual:@"archive"]) return @"Archive";
    return @"Source";
}

@interface DPLocalRemoveButton : NSButton
@property (nonatomic, copy) NSString *path;
@end

@implementation DPLocalRemoveButton

- (void)remove:(id)sender {
    NSError *error = nil;
    if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:self.path] resultingItemURL:NULL error:&error]) {
        DPLocalAlert(@"Couldn’t remove that tweak", error.localizedDescription ?: @"Unknown error.");
        return;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

@end

@interface DPLocalStatusView : NSStackView
@end

@implementation DPLocalStatusView

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.spacing = 8;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:DPPatchesDidChangeNotification object:nil];
    [self sync];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)sync {
    for (NSView *view in self.arrangedSubviews.copy) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSDictionary *> *items = DPLocalItems();
    if (!items.count) {
        [self addArrangedSubview:DPLabel(@"Nothing here yet. Click Add Tweak…, click New Starter Tweak…, or drop a .m file, "
                                          "a GitHub PR .patch or a .dylib into the folder.",
                                          11, NSFontWeightRegular, NSColor.secondaryLabelColor)];
        return;
    }
    for (NSDictionary *item in items) {
        NSMutableArray<NSString *> *keys = [NSMutableArray new];
        for (NSDictionary *patch in item[@"patches"])
            if (patch[@"title"]) [keys addObject:patch[@"title"]];
        NSString *title = keys.count ? [keys componentsJoinedByString:@", "] : item[@"id"];
        NSString *detail = [NSString stringWithFormat:@"%@ · %@ · %@", item[@"id"], DPLocalKindText(item[@"kind"]), DPLocalStatusText(item[@"status"])];
        NSMutableArray<NSView *> *lines = [NSMutableArray arrayWithObjects:DPLabel(title, 13, NSFontWeightRegular, NSColor.labelColor),
                                                                           DPLabel(detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), nil];
        if (item[@"error"]) [lines addObject:DPLabel(item[@"error"], 11, NSFontWeightRegular, NSColor.systemRedColor)];
        DPLocalRemoveButton *remove = [DPLocalRemoveButton buttonWithTitle:@"Remove" target:nil action:@selector(remove:)];
        remove.controlSize = NSControlSizeSmall;
        remove.bezelStyle = NSBezelStyleInline;
        remove.target = remove;
        remove.path = item[@"path"];
        [self addArrangedSubview:DPRow(DPColumn(lines, 2), remove)];
    }
}

@end

@interface DPLocalActions : NSObject
@end

@implementation DPLocalActions

- (void)report:(NSString *)text {
    if (text.length) DPLocalAlert(@"Local Tweaks", text);
}

- (void)refresh {
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

- (void)buildAll:(void (^)(BOOL ok, NSString *report))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = nil;
        BOOL ok = DPLocalBuildAll(nil, &report);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refresh];
            done(ok, report);
        });
    });
}

- (void)buildThenOfferRelaunch {
    [self buildAll:^(BOOL ok, NSString *report) {
        if (!ok) return [self report:report];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Local tweaks are ready";
        alert.informativeText = @"Relaunch Dia to load them.";
        [alert addButtonWithTitle:@"Relaunch Dia"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
    }];
}

- (void)addTweak:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"Choose a .m file, a tweak folder, a PR .patch, a .zip or a .dylib.";
    if ([panel runModal] != NSModalResponseOK) return;
    NSMutableArray<NSString *> *added = [NSMutableArray new];
    for (NSURL *url in panel.URLs) {
        NSString *error = nil;
        NSString *destination = DPLocalAdd(url.path, &error);
        if (destination) [added addObject:destination.lastPathComponent];
        else [self report:error];
    }
    if (added.count) [self buildThenOfferRelaunch];
}

- (void)newStarter:(id)sender {
    NSString *folder = DPLocalFolder();
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    DPLocalWriteReadme();
    NSString *name = @"MyTweak";
    for (int i = 2; i < 1000; i++) {
        if (![NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:[name stringByAppendingString:@".m"]]]) break;
        name = [NSString stringWithFormat:@"MyTweak %d", i];
    }
    NSString *path = [folder stringByAppendingPathComponent:[name stringByAppendingString:@".m"]];
    [DPLocalStarter(name) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
}

- (void)openFolder:(id)sender {
    DPLocalWriteReadme();
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:DPLocalFolder()]];
}

- (void)rebuild:(id)sender {
    [self buildAll:^(BOOL ok, NSString *report) {
        if (!ok) [self report:report];
    }];
}

- (void)relaunch:(id)sender { DPHandOffAndQuit(@[ @"apply" ]); }

- (void)turnBackOn:(id)sender {
    DPSetLocalSafeModeOff(NO);
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    [defaults setBool:YES forKey:@"localTweaks"];
    [self refresh];
    DPHandOffAndQuit(@[ @"apply" ]);
}

@end

// The master switch is a load gate, so flipping it must reach tweaks already in the table; save:NO keeps each one's own saved switch.
static void DPApplyLocalTweaks(DPPatch *patch) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *local = DPPatches[i];
        if (!DPIsLocalPatch(local)) continue;
        DPSetPatch(local, patch->on ? DPSavedOn(local) : NO, NO);
    }
}

static NSView *DPLocalActionRow(NSString *text, NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.controlSize = NSControlSizeSmall;
    button.bezelStyle = NSBezelStyleRounded;
    return DPRow(DPLabel(text, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), button);
}

NSArray<NSView *> *DPLocalRows(void) {
    static DPLocalActions *actions;
    if (!actions) actions = [DPLocalActions new];
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    if (DPLocalSafeModeOff())
        [rows addObject:DPLocalActionRow(@"Local tweaks are off because Dia quit unexpectedly. Everything else is still on.",
                                         @"Turn Local Tweaks Back On", actions, @selector(turnBackOn:))];
    [rows addObject:[[DPLocalStatusView alloc] init]];
    [rows addObject:DPLocalActionRow(@"Add a tweak you wrote, a GitHub PR .patch, or a prebuilt .dylib.", @"Add Tweak…", actions, @selector(addTweak:))];
    [rows addObject:DPLocalActionRow(@"Start from a working example you can edit.", @"New Starter Tweak…", actions, @selector(newStarter:))];
    [rows addObject:DPLocalActionRow(@"Show the folder in Finder.", @"Open Folder", actions, @selector(openFolder:))];
    [rows addObject:DPLocalActionRow(@"Compile everything again now.", @"Rebuild All", actions, @selector(rebuild:))];
    [rows addObject:DPLocalActionRow(@"New code only runs after Dia reopens.", @"Relaunch Dia", actions, @selector(relaunch:))];
    return rows;
}

DP_PATCH(DPLocalTweaks) {
    .key = @"localTweaks",
    .defaultOn = YES,
    .order = 99,
    .title = @"Local Tweaks",
    .detail = @"Run personal tweaks from your local folder — .m sources, PR .patch files or .dylibs — across Dia and DiaTweaks updates.",
    .symbol = @"hammer",
    .tint = @"systemYellowColor",
    .section = @"App",
    .relaunch = YES,
    .apply = DPApplyLocalTweaks,
    .rows = DPLocalRows,
};
