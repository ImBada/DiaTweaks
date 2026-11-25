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

static NSWindow *DPLocalSheetWindow(NSView *view) { return view.window.visible ? view.window : nil; }

static void DPLocalShow(NSAlert *alert, NSWindow *window, void (^done)(NSModalResponse response)) {
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:done];
        return;
    }
    NSModalResponse response = [alert runModal];
    if (done) done(response);
}

static void DPLocalAlert(NSWindow *window, NSString *title, NSString *text) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = text;
    DPLocalShow(alert, window, nil);
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

static NSArray<NSString *> *DPLocalKindIcon(NSString *kind) {
    if ([kind isEqual:@"patch"]) return @[ @"arrow.triangle.pull", @"systemPurpleColor" ];
    if ([kind isEqual:@"dylib"]) return @[ @"shippingbox.fill", @"systemBlueColor" ];
    if ([kind isEqual:@"archive"]) return @[ @"doc.zipper", @"systemTealColor" ];
    return @[ @"hammer.fill", @"systemOrangeColor" ];
}

static NSArray<NSString *> *DPLocalIcon(NSDictionary *item) {
    NSString *status = item[@"status"];
    if (![@[ @"loaded", @"ready", @"incompatible" ] containsObject:status]) return @[ @"exclamationmark.triangle.fill", @"systemRedColor" ];
    if ([status isEqual:@"incompatible"]) return @[ @"exclamationmark.triangle.fill", @"systemOrangeColor" ];
    NSDictionary *first = [item[@"patches"] firstObject];
    DPPatch *live = first[@"key"] ? DPPatchNamed(first[@"key"]) : NULL;
    NSString *symbol = first[@"symbol"], *tint = first[@"tint"];
    if (!symbol.length && live) {
        symbol = live->symbol;
        tint = live->tint;
    }
    return symbol.length ? @[ symbol, tint ?: @"" ] : DPLocalKindIcon(item[@"kind"]);
}

static NSTextField *DPLocalPrimary(NSString *text) { return DPLabel(text, 13, NSFontWeightRegular, NSColor.labelColor); }

static NSTextField *DPLocalSecondary(NSString *text) { return DPLabel(text, 11, NSFontWeightRegular, NSColor.secondaryLabelColor); }

static NSView *DPLocalRow(NSString *title, NSTextField *detail, NSView *trailing) {
    return DPRow(DPColumn(@[ DPLocalPrimary(title), detail ], 2), trailing);
}

static NSView *DPLocalCard(NSString *title, NSArray<NSView *> *rows) {
    NSView *card = DPGroup(rows);
    card.identifier = title;
    return card;
}

static NSProgressIndicator *DPLocalSpinner(void) {
    NSProgressIndicator *spinner = [NSProgressIndicator new];
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.controlSize = NSControlSizeSmall;
    return spinner;
}

static NSString *DPLocalRebuiltText(void) {
    NSArray<NSDictionary *> *items = DPLocalItems();
    if (!items.count) return @"No local tweaks to build.";
    for (NSDictionary *item in items)
        if ([item[@"status"] isEqual:@"ready"]) return @"Rebuilt — relaunch Dia to load changes.";
    return @"All local tweaks built cleanly.";
}

@interface DPLocalButton : NSButton
@property (nonatomic, copy) id payload;
@end

@implementation DPLocalButton
@end

extern DPPatch DPLocalTweaks;

static char DPLocalPageKey;

@interface DPLocalPage : NSObject
+ (NSArray<NSView *> *)cards;
@end

@implementation DPLocalPage {
    __weak NSView *_installed, *_available;
    NSArray<NSDictionary *> *_items, *_catalog;
    NSDictionary *_availableState;
    NSString *_catalogError, *_stamp;
    NSMutableSet<NSString *> *_installing;
    NSMutableArray<NSButton *> *_removeButtons, *_installButtons;
    NSButton *_turnOn, *_add, *_starter, *_open, *_rebuild, *_relaunch;
    NSTextField *_rebuildDetail, *_relaunchDetail;
    NSProgressIndicator *_spinner;
    NSString *_rebuilt;
    BOOL _building, _loadingCatalog, _stale;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:title target:self action:action];
}

+ (NSArray<NSView *> *)cards { return [[self new] makeCards]; }

- (NSArray<NSView *> *)makeCards {
    _removeButtons = [NSMutableArray new];
    _installButtons = [NSMutableArray new];
    _installing = [NSMutableSet new];
    _catalog = DPLocalCachedCatalog();
    _loadingCatalog = !_catalog;
    NSMutableArray<NSView *> *cards = [NSMutableArray new];
    if (DPLocalSafeModeOff()) {
        _turnOn = [self button:@"Turn Local Tweaks Back On" action:@selector(turnBackOn:)];
        NSStackView *heading = DPHeading(@"exclamationmark.triangle.fill", @"systemOrangeColor", @[
            DPLocalPrimary(@"Local tweaks are off"),
            DPLocalSecondary(@"Dia quit unexpectedly right after opening. Built-in tweaks are still on."),
        ]);
        [cards addObject:DPLocalCard(@"Safe Mode", @[ DPRow(heading, _turnOn) ])];
    }

    NSView *installed = DPLocalCard(@"Installed", @[]);
    _installed = installed;
    DPSet(installed, &DPLocalPageKey, self);  // the cards are plain groups, so this one keeps the controller alive
    [cards addObject:installed];

    NSView *available = DPLocalCard(@"Available", @[]);
    _available = available;
    [cards addObject:available];

    _add = [self button:@"Add Tweak…" action:@selector(addTweak:)];
    _starter = [self button:@"New Starter Tweak…" action:@selector(newStarter:)];
    _open = [self button:@"Open Folder" action:@selector(openFolder:)];
    [cards addObject:DPLocalCard(@"Manage", @[
        DPLocalRow(@"Add Tweak", DPLocalSecondary(@"Import a .m file, a tweak folder, a GitHub PR .patch, a .zip or a .dylib."), _add),
        DPLocalRow(@"Starter Template", DPLocalSecondary(@"Create a working .m example in your local folder and show it in Finder."), _starter),
        DPLocalRow(@"Tweaks Folder", DPLocalSecondary(@"Show ~/Library/Application Support/DiaPatches/local in Finder."), _open),
    ])];

    _rebuild = [self button:@"Rebuild All" action:@selector(rebuild:)];
    _relaunch = [self button:@"Relaunch Dia" action:@selector(relaunch:)];
    _spinner = DPLocalSpinner();
    NSStackView *progress = [NSStackView stackViewWithViews:@[ _spinner, _rebuild ]];
    progress.spacing = 8;
    progress.detachesHiddenViews = YES;
    _rebuildDetail = DPLocalSecondary(@"");
    _relaunchDetail = DPLocalSecondary(@"");
    [cards addObject:DPLocalCard(@"Build & Apply", @[
        DPLocalRow(@"Rebuild Tweaks", _rebuildDetail, progress),
        DPLocalRow(@"Relaunch Dia", _relaunchDetail, _relaunch),
    ])];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:DPPatchesDidChangeNotification object:nil];
    [self refreshCatalog];
    return cards;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (NSView *)rowForItem:(NSDictionary *)item {
    NSMutableArray<NSString *> *titles = [NSMutableArray new];
    for (NSDictionary *patch in item[@"patches"])
        if (patch[@"title"]) [titles addObject:patch[@"title"]];
    NSString *identifier = item[@"id"];
    NSString *title = titles.count ? [titles componentsJoinedByString:@", "] : identifier;
    NSString *detail = [NSString stringWithFormat:@"%@ · %@", DPLocalKindText(item[@"kind"]), DPLocalStatusText(item[@"status"])];
    if (![title isEqualToString:identifier]) detail = [NSString stringWithFormat:@"%@ · %@", identifier, detail];
    NSMutableArray<NSView *> *lines = [NSMutableArray arrayWithObjects:DPLocalPrimary(title), DPLocalSecondary(detail), nil];
    NSString *error = item[@"error"];
    if (error.length) {
        NSTextField *problem = DPLabel(error, 10.5, NSFontWeightRegular, NSColor.systemRedColor);
        problem.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
        [lines addObject:problem];
    }
    NSArray<NSString *> *icon = DPLocalIcon(item);
    NSStackView *heading = DPHeading(icon[0], icon[1], lines);
    if (error.length) heading.alignment = NSLayoutAttributeTop;
    DPLocalButton *remove = [DPLocalButton buttonWithTitle:@"Remove" target:self action:@selector(remove:)];
    remove.payload = item[@"path"];
    [_removeButtons addObject:remove];
    return DPRow(heading, remove);
}

- (NSArray<NSView *> *)installedRows {
    [_removeButtons removeAllObjects];
    if (!_items.count) {
        return @[ DPFullRow(DPHeading(@"tray", @"systemGrayColor", @[
            DPLocalPrimary(@"No local tweaks installed"),
            DPLocalSecondary(@"Drop a .m file, a GitHub PR .patch, or a .dylib into your local folder, or add one below."),
        ])) ];
    }
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    for (NSDictionary *item in _items) [rows addObject:[self rowForItem:item]];
    return rows;
}

- (NSView *)availableRowForEntry:(NSDictionary *)entry installed:(BOOL)installed previouslyOn:(BOOL)previouslyOn {
    NSDictionary *primary = DPLocalPrimaryPatch(entry);
    NSString *symbol = [primary[@"symbol"] length] ? primary[@"symbol"] : @"hammer.fill";
    NSString *tint = [primary[@"tint"] length] ? primary[@"tint"] : @"systemOrangeColor";
    NSString *detail = primary[@"detail"] ?: @"";
    if (previouslyOn) detail = [@"Previously on · " stringByAppendingString:detail];
    NSStackView *heading = DPHeading(symbol, tint, @[ DPLocalPrimary(primary[@"title"]), DPLocalSecondary(detail) ]);
    if (installed) {
        NSButton *done = [NSButton buttonWithTitle:@"Installed" target:nil action:NULL];
        done.enabled = NO;
        return DPRow(heading, done);
    }
    DPLocalButton *install = [DPLocalButton buttonWithTitle:@"Install" target:self action:@selector(install:)];
    install.payload = entry;
    if (![_installing containsObject:entry[@"id"]]) {
        [_installButtons addObject:install];
        return DPRow(heading, install);
    }
    install.enabled = NO;
    NSProgressIndicator *spinner = DPLocalSpinner();
    [spinner startAnimation:nil];
    NSStackView *progress = [NSStackView stackViewWithViews:@[ spinner, install ]];
    progress.spacing = 8;
    return DPRow(heading, progress);
}

- (void)syncAvailable {
    NSArray<NSDictionary *> *visible = _catalog ? DPLocalAvailableCatalogForItems(_catalog, _items) : @[];
    NSUserDefaults *defaults = DPSettingsDefaults();
    NSMutableArray<NSArray *> *flags = [NSMutableArray new];
    for (NSDictionary *entry in visible) {
        BOOL installed = DPLocalIsCatalogItemInstalled(entry, _items);
        BOOL previouslyOn = !installed && [[defaults objectForKey:DPLocalPrimaryPatch(entry)[@"key"]] boolValue];
        [flags addObject:@[ @(installed), @([_installing containsObject:entry[@"id"]]), @(previouslyOn) ]];
    }
    NSDictionary *state = @{ @"visible" : visible, @"flags" : flags, @"loading" : @(_loadingCatalog && !_catalog), @"error" : _catalogError ?: @"" };
    if ([state isEqualToDictionary:_availableState]) return;
    _availableState = state;
    [_installButtons removeAllObjects];

    NSArray<NSView *> *rows;
    if (_loadingCatalog && !_catalog) {
        rows = @[ DPFullRow(DPHeading(@"arrow.down.circle", @"systemBlueColor", @[
            DPLocalPrimary(@"Checking available tweaks…"),
            DPLocalSecondary(@"Looking up optional tweaks from DiaTweaks."),
        ])) ];
    } else if (!_catalog) {
        NSButton *retry = [self button:@"Retry" action:@selector(retry:)];
        rows = @[ DPRow(DPHeading(@"exclamationmark.triangle.fill", @"systemOrangeColor", @[
            DPLocalPrimary(@"Couldn’t load available tweaks"),
            DPLocalSecondary(_catalogError.length ? _catalogError : @"Try again in a moment."),
        ]), retry) ];
    } else if (!visible.count) {
        rows = @[ DPFullRow(DPHeading(@"square.and.arrow.down", @"systemGrayColor", @[
            DPLocalPrimary(@"No optional tweaks yet"),
            DPLocalSecondary(@"Tweaks moved out of the built-in list appear here to install in one click."),
        ])) ];
    } else {
        NSMutableArray<NSView *> *built = [NSMutableArray new];
        for (NSUInteger i = 0; i < visible.count; i++)
            [built addObject:[self availableRowForEntry:visible[i] installed:[flags[i][0] boolValue] previouslyOn:[flags[i][2] boolValue]]];
        rows = built;
    }
    DPSetGroupRows(_available, rows);
}

- (void)syncItems {
    NSString *stamp = [DPLocalStamp(DPLocalFolder()) stringByAppendingString:DPLocalStamp(DPLocalStatePath())];
    if (!_stale && [stamp isEqual:_stamp]) return;
    _stale = NO;
    _stamp = stamp;
    NSArray<NSDictionary *> *items = DPLocalItems();
    if ([items isEqualToArray:_items]) return;
    _items = items;
    DPSetGroupRows(_installed, [self installedRows]);
}

- (void)sync {
    if (!_installed) return;
    [self syncItems];
    [self syncAvailable];
    BOOL ready = NO;
    for (NSDictionary *item in _items) ready |= [item[@"status"] isEqual:@"ready"];
    BOOL running = !DPSafeMode && !DPPaused && !DPPausedAtLaunch, editable = running && DPLocalTweaks.on;
    for (NSButton *remove in _removeButtons) remove.enabled = running;
    _turnOn.enabled = !DPSafeMode && !DPPaused;
    _open.enabled = _relaunch.enabled = running;
    BOOL busy = _building || _installing.count;
    _add.enabled = _starter.enabled = _rebuild.enabled = editable && !busy;
    for (NSButton *install in _installButtons) install.enabled = editable && !busy;
    _rebuildDetail.stringValue = _building ? @"Building local tweaks…" : _rebuilt ?: @"Recompile every source and patch tweak in your local folder.";
    _relaunchDetail.stringValue = ready ? @"Changes are ready and will load when Dia reopens." : @"New or rebuilt tweaks take effect after Dia reopens.";
    _spinner.hidden = !_building;
    if (_building) [_spinner startAnimation:nil];
    else [_spinner stopAnimation:nil];
}

- (void)report:(NSString *)text {
    if (text.length) DPLocalAlert(DPLocalSheetWindow(_installed), @"Local Tweaks", text);
}

- (void)changed {
    _stale = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

- (void)build:(NSArray<NSString *> *)names force:(BOOL)force offerRelaunch:(BOOL)offer {
    _building = YES;
    _rebuilt = nil;
    [self sync];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = nil;
        BOOL ok = DPLocalBuildNames(names, force, &report);
        NSString *rebuilt = ok ? DPLocalRebuiltText() : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_building = NO;
            self->_rebuilt = rebuilt;
            [self changed];
            if (!ok) [self report:report];
            else if (offer) [self offerRelaunch];
        });
    });
}

- (void)offerRelaunch {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Local tweaks are ready";
    alert.informativeText = @"Relaunch Dia to load them.";
    [alert addButtonWithTitle:@"Relaunch Dia"];
    [alert addButtonWithTitle:@"Later"];
    DPLocalShow(alert, DPLocalSheetWindow(_installed), ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
    });
}

- (void)retry:(id)sender { [self refreshCatalog]; }

- (void)refreshCatalog {
    _loadingCatalog = YES;
    [self sync];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        NSArray<NSDictionary *> *catalog = DPLocalFetchCatalog(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (catalog) self->_catalog = catalog;
            self->_catalogError = catalog ? nil : error;
            self->_loadingCatalog = NO;
            [self sync];
        });
    });
}

- (void)install:(DPLocalButton *)sender {
    NSDictionary *entry = sender.payload;
    NSString *identifier = entry[@"id"];
    [_installing addObject:identifier];
    [self sync];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        BOOL ok = DPLocalInstallCatalogItem(entry, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_installing removeObject:identifier];
            [self changed];
            if (ok) [self offerRelaunch];
            else [self report:error];
        });
    });
}

- (void)addTweak:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"Choose a .m file, a tweak folder, a PR .patch, a .zip or a .dylib.";
    void (^add)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSMutableArray<NSString *> *added = [NSMutableArray new];
        for (NSURL *url in panel.URLs) {
            NSString *error = nil, *path = DPLocalAdd(url.path, &error);
            if (path) [added addObject:path.lastPathComponent.stringByDeletingPathExtension];
            else [self report:error];
        }
        if (added.count) [self build:added force:NO offerRelaunch:YES];
    };
    NSWindow *window = DPLocalSheetWindow(_installed);
    if (window) [panel beginSheetModalForWindow:window completionHandler:add];
    else add([panel runModal]);
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
    [self build:@[ name ] force:NO offerRelaunch:NO];
}

- (void)openFolder:(id)sender {
    DPLocalWriteReadme();
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:DPLocalFolder()]];
}

- (void)rebuild:(id)sender { [self build:nil force:YES offerRelaunch:NO]; }

- (void)remove:(DPLocalButton *)sender {
    NSError *error = nil;
    if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:sender.payload] resultingItemURL:NULL error:&error]) {
        DPLocalAlert(DPLocalSheetWindow(_installed), @"Couldn’t remove that tweak", error.localizedDescription ?: @"Unknown error.");
        return;
    }
    [self changed];
}

- (void)relaunch:(id)sender { DPHandOffAndQuit(@[ @"apply" ]); }

- (void)turnBackOn:(id)sender {
    DPSetLocalSafeModeOff(NO);
    [DPSettingsDefaults() setBool:YES forKey:@"localTweaks"];
    [self changed];
    DPHandOffAndQuit(@[ @"apply" ]);
}

@end

static void DPApplyLocalTweaks(DPPatch *patch) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *local = DPPatches[i];
        if (!DPIsLocalPatch(local)) continue;
        DPSetPatch(local, patch->on ? DPSavedOn(local) : NO, NO);
    }
}

NSArray<NSView *> *DPLocalRows(void) { return DPLocalPage.cards; }

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
