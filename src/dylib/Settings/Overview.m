#import "Settings.h"

static void DPAppendSearch(NSMutableString *search, DPPatch *patch) {
    [search appendFormat:@" %@ %@ %@", patch->title, patch->detail, patch->experimental ? @"experimental" : @""];
    DPForEachOption(patch, ^(DPPatch *option) { [search appendFormat:@" %@ %@", option->title, option->detail]; });
}

@interface DPFolderRow : NSObject
@property (nonatomic, assign) const DPFolderSpec *spec;
@property (nonatomic, strong) NSArray<NSValue *> *members;
@property (nonatomic, strong) NSTextField *note;
@property (nonatomic, strong) NSImageView *eye;
@end

@implementation DPFolderRow
@end

@interface DPOverviewSection : NSObject
@property (nonatomic, strong) NSView *header, *group;
@property (nonatomic, strong) NSArray<NSView *> *rows;
@end

@implementation DPOverviewSection
@end

@interface DPOverviewView ()
@property (nonatomic, strong) NSMutableArray<NSArray *> *toggles;
@property (nonatomic, strong) NSMapTable<NSView *, NSArray<NSValue *> *> *gates;
@property (nonatomic, strong) NSMutableArray<DPOverviewSection *> *sections;
@property (nonatomic, strong) NSMutableArray<DPFolderRow *> *folders;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *sectionHiders;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSImageView *> *sectionEyes;
@property (nonatomic, strong) NSTextField *noResults;
@property (nonatomic, strong) NSView *pausedRow, *experimentalRow;
@property (nonatomic, strong) NSTextField *pauseLabel, *experimentalLabel;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic) NSUInteger hiddenExperimental;
@end

@implementation DPOverviewView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.searchText = [NSMapTable strongToStrongObjectsMapTable];
    self.toggles = [NSMutableArray new];
    self.gates = [NSMapTable strongToStrongObjectsMapTable];
    self.sections = [NSMutableArray new];
    self.folders = [NSMutableArray new];
    self.sectionHiders = [NSMutableDictionary new];
    self.sectionEyes = [NSMutableDictionary new];

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
    NSMutableSet<NSString *> *folded = [NSMutableSet new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        if (DPRequired(patch)) continue;
        NSString *section = patch->section ?: @"Other", *hider = patch->disabledBy ?: @"", *shared = self.sectionHiders[section];
        self.sectionHiders[section] = !shared || [shared isEqual:hider] ? hider : @"";
        const DPFolderSpec *folder = patch->group ? DPFolderSpecNamed(patch->group) : NULL;
        if (!folder) {
            add(section, [self rowForPatch:patch]);
            continue;
        }
        if ([folded containsObject:patch->group]) continue;
        [folded addObject:patch->group];
        add(section, [self rowForFolder:folder]);
    }
    add(@"Experimental", self.experimentalRow = [self makeExperimentalRow]);

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
        DPOverviewSection *section = [DPOverviewSection new];
        section.header = header;
        section.group = group;
        section.rows = rows[title];
        [self.sections addObject:section];
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

- (NSView *)makeExperimentalRow {
    self.experimentalLabel = DPLabel(@"", 13, NSFontWeightRegular, NSColor.labelColor);
    NSView *row = DPRow(self.experimentalLabel, [NSButton buttonWithTitle:@"Show" target:self action:@selector(showExperimental:)]);
    [self.searchText setObject:@"experimental hidden tweaks show still being tested" forKey:row];
    return row;
}

- (void)showExperimental:(id)sender { DPSetShowsExperimental(YES); }

- (NSView *)rowForPatch:(DPPatch *)patch {
    NSTextField *note = DPHiddenNote();
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [self.toggles addObject:@[ toggle, note ]];
    NSMutableString *search = [NSMutableString new];
    DPAppendSearch(search, patch);

    __weak DPOverviewView *weakSelf = self;
    NSStackView *heading = DPHeading(patch->symbol, patch->tint, @[ DPLabel(patch->title, 13, NSFontWeightRegular, NSColor.labelColor), note ]);
    NSView *row = DPLinkRow(DPRow(heading, DPDisclosure(toggle.withHiddenIcon)), patch->title, ^{
        if (weakSelf.open) weakSelf.open(patch->title, [[DPPageView alloc] initWithPatch:patch]);
    });
    [self.searchText setObject:search forKey:row];
    [self.gates setObject:@[ [NSValue valueWithPointer:patch] ] forKey:row];
    return row;
}

- (NSView *)rowForFolder:(const DPFolderSpec *)folder {
    NSTextField *note = DPHiddenNote();
    NSImageView *eye = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
    NSArray<NSValue *> *members = DPFolderMembers(folder->key);
    DPFolderRow *entry = [DPFolderRow new];
    entry.spec = folder;
    entry.members = members;
    entry.note = note;
    entry.eye = eye;
    [self.folders addObject:entry];

    NSMutableString *search = [NSMutableString stringWithFormat:@"%@ %@", folder->title, folder->detail];
    for (NSValue *value in members) DPAppendSearch(search, value.pointerValue);

    __weak DPOverviewView *weakSelf = self;
    NSStackView *heading = DPHeading(folder->symbol, folder->tint, @[ DPLabel(folder->title, 13, NSFontWeightRegular, NSColor.labelColor), note ]);
    NSView *row = DPLinkRow(DPRow(heading, DPDisclosure(eye)), folder->title, ^{
        if (weakSelf.open) weakSelf.open(folder->title, [[DPFolderView alloc] initWithFolder:folder]);
    });
    [self.searchText setObject:search forKey:row];
    [self.gates setObject:members forKey:row];
    return row;
}

- (void)syncFolder:(DPFolderRow *)entry {
    NSArray<NSValue *> *members = DPShownMembers(entry.members);
    NSString *shared = nil;
    BOOL every = members.count > 0;
    for (NSValue *value in members) {
        DPPatch *member = value.pointerValue;
        NSString *why = DPWhyDisabled(member);
        if (!why || (shared && ![shared isEqualToString:why])) {
            every = NO;
            break;
        }
        shared = why;
    }
    NSMutableArray<NSString *> *shown = [NSMutableArray new];
    for (NSValue *value in members) {
        DPPatch *member = value.pointerValue;
        if (DPShownOn(member)) [shown addObject:member->title];
    }
    NSString *note = every ? [shared stringByReplacingOccurrencesOfString:@"this" withString:@"these"]
                           : [shown componentsJoinedByString:@" · "];
    entry.note.stringValue = note ?: @"";
    entry.note.hidden = !entry.note.stringValue.length;

    NSString *hint = nil;
    if (shown.count) {
        for (NSValue *value in members) {
            if (!DPShownOn(value.pointerValue)) continue;
            NSString *why = DPWhyHidden(value.pointerValue);
            if (!why || (hint && ![hint isEqualToString:why])) {
                hint = nil;
                break;
            }
            hint = why;
        }
    }
    if (self.sectionEyes[entry.spec->section] && !self.sectionEyes[entry.spec->section].hidden) hint = nil;
    DPSetHint(entry.eye, hint);
    entry.eye.hidden = !hint;
}

- (void)syncState {
    DPSyncPauseRow(self.pauseLabel, self.pauseButton);
    self.hiddenExperimental = DPHiddenExperimentalCount();
    self.experimentalLabel.stringValue = [NSString stringWithFormat:@"%lu experimental tweak%@ hidden.", self.hiddenExperimental,
                                          self.hiddenExperimental == 1 ? @" is" : @"s are"];
    [self.sectionEyes enumerateKeysAndObjectsUsingBlock:^(NSString *section, NSImageView *eye, BOOL *stop) {
        NSString *hint = DPWhyHiddenBy(DPPatchNamed(self.sectionHiders[section]));
        DPSetHint(eye, hint);
        eye.hidden = !hint;
    }];
    for (NSArray *pair in self.toggles) {
        DPPatchSwitch *toggle = pair[0];
        NSTextField *note = pair[1];
        [toggle sync];
        if (self.sectionEyes[toggle.patch->section ?: @"Other"]) toggle.hiddenIcon.hidden = YES;
        note.stringValue = DPActiveSummary(toggle.patch) ?: @"";
        note.hidden = !note.stringValue.length;
    }
    for (DPFolderRow *folder in self.folders) [self syncFolder:folder];
}

- (void)filterWithQuery:(NSString *)query {
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL anything = NO;
    for (DPOverviewSection *section in self.sections) {
        for (NSView *row in section.rows) {
            NSArray<NSValue *> *gate = [self.gates objectForKey:row];
            BOOL visible = row == self.pausedRow ? DPPaused || !DPSafeMode : row == self.experimentalRow ? self.hiddenExperimental > 0 : !gate || DPShownMembers(gate).count;
            NSString *text = visible ? [self.searchText objectForKey:row] : nil;
            for (NSString *word in words) {
                if (!visible) break;
                if (word.length && ![text localizedStandardContainsString:word]) visible = NO;
            }
            row.hidden = !visible;
        }
        BOOL any = DPTidyGroup(section.group);
        section.header.hidden = !any || (section.rows.firstObject == self.pausedRow && !DPPaused);
        anything |= any;
    }
    self.noResults.hidden = anything;
}

- (void)syncWithQuery:(NSString *)query {
    [self syncState];
    [self filterWithQuery:query];
}
@end
