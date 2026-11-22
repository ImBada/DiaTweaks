#import "Settings.h"

@interface DPOverviewView ()
@property (nonatomic, strong) NSMapTable<DPPatchSwitch *, NSTextField *> *notes;
@property (nonatomic, strong) NSMutableArray<NSArray *> *sections;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *sectionHiders;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSImageView *> *sectionEyes;
@property (nonatomic, strong) NSTextField *noResults;
@property (nonatomic, strong) NSView *pausedRow;
@property (nonatomic, strong) NSTextField *pauseLabel;
@property (nonatomic, strong) NSButton *pauseButton;
@end

@implementation DPOverviewView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.searchText = [NSMapTable strongToStrongObjectsMapTable];
    self.notes = [NSMapTable strongToStrongObjectsMapTable];
    self.sections = [NSMutableArray new];
    self.sectionHiders = [NSMutableDictionary new];
    self.sectionEyes = [NSMutableDictionary new];
    [DPPreviewView preload];

    NSMutableArray<NSString *> *titles = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<NSView *> *> *rows = [NSMutableDictionary new];
    void (^add)(NSString *, NSView *) = ^(NSString *title, NSView *row) {
        if (!rows[title]) {
            [titles addObject:title];
            rows[title] = [NSMutableArray new];
        }
        [rows[title] addObject:row];
    };
    if (DPSafeMode) add(@"Safe Mode", [self makeSafeModeRow]);
    // Always built, so pausing from Terminal shows up here without reopening Settings.
    add(@"Paused", self.pausedRow = [self makePausedRow]);
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        if (DPRequired(patch)) continue;
        NSString *section = patch->section ?: @"Other", *hider = patch->disabledBy ?: @"", *shared = self.sectionHiders[section];
        self.sectionHiders[section] = !shared || [shared isEqual:hider] ? hider : @"";
        add(section, [self rowForPatch:patch]);
    }

    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSString *title in titles) {
        NSView *header = DPHeader(title);
        if (self.sectionHiders[title].length) {
            NSImageView *eye = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
            self.sectionEyes[title] = eye;
            NSStackView *row = [NSStackView new];
            row.detachesHiddenViews = NO;
            [row addView:header inGravity:NSStackViewGravityLeading];
            [row addView:eye inGravity:NSStackViewGravityTrailing];
            header = row;
        }
        NSView *group = DPGroup(rows[title]);
        [views addObjectsFromArray:@[header, group]];
        [self.sections addObject:@[header, group, rows[title]]];
    }
    self.noResults = DPLabel(@"No Results", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    DPFillStack(self, [views arrayByAddingObject:self.noResults]);
    [self syncWithQuery:@""];
    return self;
}

- (NSView *)makeSafeModeRow {
    NSView *row = DPRow(DPLabel(@"Patches are off because Dia quit unexpectedly right after opening.", 13, NSFontWeightRegular, NSColor.labelColor),
                        [NSButton buttonWithTitle:@"Turn Patches Back On" target:self action:@selector(leaveSafeMode:)]);
    [self.searchText setObject:@"Safe mode patches off crashed quit unexpectedly turn back on" forKey:row];
    return row;
}

- (void)leaveSafeMode:(id)sender {
    DPLeaveSafeMode();
    DPHandOffAndQuit(@[@"apply"]);
}

- (NSView *)makePausedRow {
    self.pauseLabel = DPLabel(@"", 13, NSFontWeightRegular, NSColor.labelColor);
    self.pauseButton = [NSButton buttonWithTitle:@"" target:self action:@selector(togglePause:)];
    DPSyncPauseRow(self.pauseLabel, self.pauseButton);
    NSView *row = DPRow(self.pauseLabel, self.pauseButton);
    [self.searchText setObject:@"pause paused pause tweaks disable all turn off all resume turn patches back on" forKey:row];
    return row;
}

- (void)togglePause:(id)sender {
    DPSetTweaksPaused(!DPPaused, self.window);
}

- (NSView *)rowForPatch:(DPPatch *)patch {
    NSTextField *note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    note.hidden = YES;
    SEL tintSel = patch->tint.length ? NSSelectorFromString(patch->tint) : NULL;
    NSColor *tint = tintSel && [NSColor respondsToSelector:tintSel] ? [NSColor valueForKey:patch->tint] : NSColor.systemGrayColor;
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTile(patch->symbol, tint),
        DPColumn(@[DPLabel(patch->title, 13, NSFontWeightRegular, NSColor.labelColor), note], 2),
    ]];
    leading.spacing = 10;

    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [self.notes setObject:note forKey:toggle];
    NSMutableString *search = [NSMutableString stringWithFormat:@"%@ %@", patch->title, patch->detail];
    DPForEachOption(patch, ^(DPPatch *option) { [search appendFormat:@" %@ %@", option->title, option->detail]; });
    NSStackView *trailing = [NSStackView stackViewWithViews:@[toggle.withHiddenIcon, DPSymbol(@"chevron.right", 11, NSColor.tertiaryLabelColor)]];
    trailing.spacing = 10;

    __weak DPOverviewView *weakSelf = self;
    NSView *row = DPLinkRow(DPRow(leading, trailing), patch->title, ^{
        if (weakSelf.open) weakSelf.open(patch->title, [[DPPageView alloc] initWithPatch:patch]);
    });
    [self.searchText setObject:search forKey:row];
    return row;
}

- (void)syncWithQuery:(NSString *)query {
    DPSyncPauseRow(self.pauseLabel, self.pauseButton);
    [self.sectionEyes enumerateKeysAndObjectsUsingBlock:^(NSString *section, NSImageView *eye, BOOL *stop) {
        NSString *hint = DPWhyHiddenBy(DPPatchNamed(self.sectionHiders[section]));
        DPSetHint(eye, hint);
        eye.hidden = !hint;
    }];
    for (DPPatchSwitch *toggle in self.notes) {
        [toggle sync];
        if (self.sectionEyes[toggle.patch->section ?: @"Other"]) toggle.hiddenIcon.hidden = YES;
        NSString *summary = DPWhyDisabled(toggle.patch);
        if (!summary && (DPPaused ? DPSavedOn(toggle.patch) : toggle.patch->on)) {
            NSMutableArray<NSString *> *options = [NSMutableArray new];
            DPForEachOption(toggle.patch, ^(DPPatch *option) {
                if (DPPaused ? DPSavedOn(option) : option->on) [options addObject:option->title];
            });
            summary = [options componentsJoinedByString:@" · "];
        }
        NSTextField *note = [self.notes objectForKey:toggle];
        note.stringValue = summary ?: @"";
        note.hidden = !note.stringValue.length;
    }

    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL anything = NO;
    for (NSArray *section in self.sections) {
        BOOL any = NO;
        for (NSView *row in section[2]) {
            BOOL visible = row != self.pausedRow || DPPaused || !DPSafeMode;
            NSString *text = visible ? [self.searchText objectForKey:row] : nil;
            for (NSString *word in words) {
                if (!visible) break;
                if (word.length && ![text localizedStandardContainsString:word]) visible = NO;
            }
            NSArray<NSView *> *arranged = ((NSStackView *)row.superview).arrangedSubviews;
            NSUInteger index = [arranged indexOfObject:row];
            row.hidden = !visible;
            if (index != NSNotFound && index > 0) arranged[index - 1].hidden = !visible || !any;
            any |= visible;
        }
        BOOL pauseSection = ((NSArray *)section[2]).firstObject == self.pausedRow;
        ((NSView *)section[0]).hidden = !any || (pauseSection && !DPPaused);
        ((NSView *)section[1]).hidden = !any;
        anything |= any;
    }
    self.noResults.hidden = anything;
}
@end
