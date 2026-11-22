#import "Settings.h"

static NSString *const DPRepo = @"https://github.com/JaceThings/DiaTweaks";

static NSView *DPWebRow(NSString *title, NSString *path) {
    NSURL *url = [NSURL URLWithString:[DPRepo stringByAppendingString:path]];
    return DPLinkRow(DPRow(DPLabel(title, 13, NSFontWeightRegular, NSColor.labelColor), DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                     title, ^{ [NSWorkspace.sharedWorkspace openURL:url]; });
}

@implementation DPHomeView {
    NSTextField *_version, *_updateSummary, *_pauseLabel;
    NSButton *_pauseButton;
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
    NSStackView *trailing = [NSStackView stackViewWithViews:@[_updateSummary, DPSymbol(@"chevron.right", 11, NSColor.tertiaryLabelColor)]];
    trailing.spacing = 10;
    __weak DPHomeView *weakSelf = self;
    NSView *updateRow = DPLinkRow(DPRow(leading, trailing), @"Software Update", ^{
        if (weakSelf.open) weakSelf.open(@"Software Update", [DPSoftwareUpdateView new]);
    });
    _pauseLabel = DPLabel(@"", 13, NSFontWeightRegular, NSColor.labelColor);
    _pauseButton = [NSButton buttonWithTitle:@"" target:self action:@selector(togglePause:)];
    NSView *pauseRow = DPRow(_pauseLabel, _pauseButton);
    NSView *restoreRow = DPRow(DPLabel(@"Restore the original Dia without patches.", 13, NSFontWeightRegular, NSColor.labelColor),
                               [NSButton buttonWithTitle:@"Restore…" target:self action:@selector(restore:)]);

    NSTextField *notice = DPLabel(@"DiaTweaks is unofficial and not affiliated with The Browser Company.", 11, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    NSView *help = DPGroup(@[DPWebRow(@"Wiki", @"/wiki"), DPWebRow(@"Report a Bug", @"/issues/new/choose"), DPWebRow(@"GitHub", @"")]);
    DPFillStack(self, @[about, DPGroup(@[updateRow]), DPHeader(@"Help"), help, DPGroup(@[pauseRow, restoreRow]), notice]);
    [self setCustomSpacing:20 afterView:about];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatesDidChange) name:DPUpdatesDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncPause) name:DPPatchesDidChangeNotification object:nil];
    [self updatesDidChange];
    [self syncPause];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)updatesDidChange {
    DPUpdates *updates = DPUpdates.shared;
    NSUInteger available = 0, staged = 0;
    for (NSString *part in @[DPDia, DPTweaks]) {
        available += [updates available:part];
        staged += [updates staged:part];
    }
    _updateSummary.stringValue = staged ? @"Ready to install"
        : available ? [NSString stringWithFormat:@"%lu update%@", available, available == 1 ? @"" : @"s"]
        : updates.checking ? @"Checking…"
        : updates.checkProblem ? @"Couldn’t check"
        : updates.found ? @"Up to date" : @"";

    static NSCharacterSet *vSet;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ vSet = [NSCharacterSet characterSetWithCharactersInString:@"v"]; });
    id installed = updates.found[DPTweaks][@"installed"];
    _version.stringValue = [installed isKindOfClass:NSString.class] ? [@"Version " stringByAppendingString:[installed stringByTrimmingCharactersInSet:vSet]]
        : updates.found ? @"Development build" : @"";
    _version.hidden = !_version.stringValue.length;
}

- (void)syncPause { DPSyncPauseRow(_pauseLabel, _pauseButton); }

- (void)togglePause:(id)sender { DPSetTweaksPaused(!DPPaused, self.window); }

- (void)refresh {
    [self updatesDidChange];
    [self syncPause];
    [DPUpdates.shared check:nil];
}

- (void)restore:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Restore the original Dia?";
    alert.informativeText = @"Dia will relaunch without patches, and its own updater takes over again. Run the installer to patch it again later.";
    [alert addButtonWithTitle:@"Restore and Relaunch"];
    [alert addButtonWithTitle:@"Cancel"];
    void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"uninstall"]);
    };
    if (self.window) [alert beginSheetModalForWindow:self.window completionHandler:finish];
    else finish([alert runModal]);
}
@end
