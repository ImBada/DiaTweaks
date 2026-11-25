#import "Settings.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const DPRepo = @"https://github.com/JaceThings/DiaTweaks";

static NSView *DPWebRow(NSString *title, NSString *path) {
    NSURL *url = [NSURL URLWithString:[DPRepo stringByAppendingString:path]];
    return DPLinkRow(DPRow(DPLabel(title, 13, NSFontWeightRegular, NSColor.labelColor), DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                     title, ^{ [NSWorkspace.sharedWorkspace openURL:url]; });
}

static NSString *DPUpdateSummary(DPUpdates *updates) {
    NSUInteger available = 0, staged = 0;
    for (NSString *part in @[DPDia, DPTweaks]) {
        available += [updates available:part];
        staged += [updates staged:part];
    }
    if (staged) return @"Ready to install";
    if (available) return [NSString stringWithFormat:@"%lu update%@", available, available == 1 ? @"" : @"s"];
    if (updates.checking) return @"Checking…";
    if (updates.checkProblem) return @"Couldn’t check";
    return updates.found ? @"Up to date" : @"";
}

@implementation DPHomeView {
    NSTextField *_version, *_updateSummary, *_pauseLabel;
    NSButton *_pauseButton;
    NSSwitch *_experimental;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _version = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSStackView *about = DPColumn(@[DPIconTileOfSize(@"wand.and.stars", NSColor.systemPurpleColor, 56),
                                    DPLabel(@"DiaTweaks", 15, NSFontWeightSemibold, NSColor.labelColor), _version], 2);
    about.alignment = NSLayoutAttributeCenterX;
    [about setCustomSpacing:10 afterView:about.arrangedSubviews.firstObject];

    _updateSummary = DPLabel(@"", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTile(@"gearshape.arrow.triangle.2.circlepath", NSColor.systemGrayColor),
        DPLabel(@"Software Update", 13, NSFontWeightRegular, NSColor.labelColor),
    ]];
    leading.spacing = 10;
    __weak DPHomeView *weakSelf = self;
    NSView *updateRow = DPLinkRow(DPRow(leading, DPDisclosure(_updateSummary)), @"Software Update", ^{
        if (weakSelf.open) weakSelf.open(@"Software Update", [DPSoftwareUpdateView new]);
    });
    _pauseLabel = DPLabel(@"", 13, NSFontWeightRegular, NSColor.labelColor);
    _pauseButton = [NSButton buttonWithTitle:@"" target:self action:@selector(togglePause:)];
    NSView *pauseRow = DPRow(_pauseLabel, _pauseButton);
    NSView *restoreRow = DPRow(DPLabel(@"Restore the original Dia without patches.", 13, NSFontWeightRegular, NSColor.labelColor),
                               [NSButton buttonWithTitle:@"Restore…" target:self action:@selector(restore:)]);

    _experimental = [NSSwitch new];
    _experimental.controlSize = NSControlSizeSmall;
    _experimental.accessibilityLabel = @"Show Experimental Tweaks";
    _experimental.target = self;
    _experimental.action = @selector(toggleExperimental:);
    NSView *experimentalRow = DPRow(DPColumn(@[DPLabel(@"Show Experimental Tweaks", 13, NSFontWeightRegular, NSColor.labelColor),
                                               DPLabel(@"Show tweaks that are still being tested and may break when Dia updates.", 11, NSFontWeightRegular, NSColor.secondaryLabelColor)], 2),
                                    _experimental);
    NSView *fileRows = DPGroup(@[
        DPRow(DPLabel(@"Save your tweaks and their settings to a file.", 13, NSFontWeightRegular, NSColor.labelColor),
              [NSButton buttonWithTitle:@"Export…" target:self action:@selector(exportSettings:)]),
        DPRow(DPLabel(@"Load tweaks and settings from a file.", 13, NSFontWeightRegular, NSColor.labelColor),
              [NSButton buttonWithTitle:@"Import…" target:self action:@selector(importSettings:)]),
    ]);

    NSTextField *notice = DPLabel(@"DiaTweaks is unofficial and not affiliated with The Browser Company.", 11, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    NSView *help = DPGroup(@[DPWebRow(@"Wiki", @"/wiki"), DPWebRow(@"Report a Bug", @"/issues/new/choose"), DPWebRow(@"GitHub", @"")]);
    DPFillStack(self, @[about, DPGroup(@[updateRow]), DPGroup(@[experimentalRow]), DPHeader(@"Settings File"), fileRows, DPHeader(@"Help"), help,
                        DPGroup(@[pauseRow, restoreRow]), notice]);
    [self setCustomSpacing:20 afterView:about];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatesDidChange) name:DPUpdatesDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncRows) name:DPPatchesDidChangeNotification object:nil];
    [self updatesDidChange];
    [self syncRows];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)updatesDidChange {
    DPUpdates *updates = DPUpdates.shared;
    _updateSummary.stringValue = DPUpdateSummary(updates);

    id installed = updates.found[DPTweaks][@"installed"];
    if ([installed isKindOfClass:NSString.class]) _version.stringValue = [@"Version " stringByAppendingString:[installed hasPrefix:@"v"] ? [installed substringFromIndex:1] : installed];
    else _version.stringValue = updates.found ? @"Development build" : @"";
    _version.hidden = !_version.stringValue.length;
}

- (void)syncRows {
    DPSyncPauseRow(_pauseLabel, _pauseButton);
    _experimental.state = DPShowsExperimental() ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleExperimental:(NSSwitch *)sender { DPSetShowsExperimental(sender.state == NSControlStateValueOn); }

- (void)togglePause:(id)sender { DPSetTweaksPaused(!DPPaused, self.window); }

- (void)refresh {
    [self updatesDidChange];
    [self syncRows];
    [DPUpdates.shared check:nil];
}

- (void)restore:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Restore the original Dia?";
    alert.informativeText = @"Dia will relaunch without patches, and its own updater takes over again. Run the installer to patch it again later.";
    [alert addButtonWithTitle:@"Restore and Relaunch"];
    [alert addButtonWithTitle:@"Cancel"];
    DPPresentAlert(alert, self.window, ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"uninstall"]);
    });
}

- (void)report:(NSString *)title text:(NSString *)text {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = text ?: @"";
    DPPresentAlert(alert, self.window, ^(NSModalResponse response) {});
}

- (void)exportSettings:(id)sender {
    NSError *error = nil;
    NSData *json = DPExportConfigJSON(&error);
    if (!json) return [self report:@"Couldn’t export settings" text:error.localizedDescription];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[ UTTypeJSON ];
    panel.nameFieldStringValue = @"diatweaks-config.json";
    DPPresentPanel(panel, self.window, ^(NSModalResponse response) {
        NSError *writeError = nil;
        if (response == NSModalResponseOK && ![json writeToURL:panel.URL options:NSDataWritingAtomic error:&writeError])
            [self report:@"Couldn’t save the file" text:writeError.localizedDescription];
    });
}

- (void)importSettings:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[ UTTypeJSON ];
    DPPresentPanel(panel, self.window, ^(NSModalResponse response) {
        NSError *error = nil;
        NSData *data = response == NSModalResponseOK ? [NSData dataWithContentsOfURL:panel.URL options:0 error:&error] : nil;
        if (data) [self confirmImport:data];
        else if (response == NSModalResponseOK) [self report:@"Couldn’t read the file" text:error.localizedDescription];
    });
}

- (void)confirmImport:(NSData *)data {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Import settings?";
    alert.informativeText = @"Merge changes only what the file mentions. Replace All also puts every other tweak and setting back to its default.";
    for (NSString *title in @[ @"Merge", @"Replace All", @"Cancel" ]) [alert addButtonWithTitle:title];
    DPPresentAlert(alert, self.window, ^(NSModalResponse response) {
        if (response == NSAlertThirdButtonReturn) return;
        NSError *error = nil;
        DPConfigImport *result = DPImportConfigData(data, response == NSAlertSecondButtonReturn, &error);
        if (result) [self summarize:result];
        else [self report:@"Couldn’t import settings" text:error.localizedDescription];
    });
}

- (void)summarize:(DPConfigImport *)result {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    NSString *applied = [NSString stringWithFormat:@"%lu setting%@ applied", result.appliedCount, result.appliedCount == 1 ? @"" : @"s"];
    [lines addObject:result.resetCount ? [applied stringByAppendingFormat:@" and %lu reset to default.", result.resetCount] : [applied stringByAppendingString:@"."]];
    [lines addObjectsFromArray:result.warnings];
    if (result.unknownKeys.count) [lines addObject:[@"Skipped what this version doesn’t know: " stringByAppendingFormat:@"%@.", [result.unknownKeys componentsJoinedByString:@", "]]];
    if (result.relaunchTitles.count) [lines addObject:[@"Relaunch Dia to finish: " stringByAppendingFormat:@"%@.", [result.relaunchTitles componentsJoinedByString:@", "]]];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Settings imported";
    alert.informativeText = [lines componentsJoinedByString:@"\n"];
    [alert addButtonWithTitle:result.relaunchTitles.count ? @"Relaunch Now" : @"OK"];
    if (result.relaunchTitles.count) [alert addButtonWithTitle:@"Later"];
    BOOL relaunch = result.relaunchTitles.count > 0;
    DPPresentAlert(alert, self.window, ^(NSModalResponse response) {
        if (relaunch && response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"apply"]);
    });
}
@end
