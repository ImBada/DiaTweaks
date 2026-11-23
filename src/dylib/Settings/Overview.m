#import "Settings.h"

static void DPAppendSearch(NSMutableString *search, DPPatch *patch) {
    [search appendFormat:@" %@ %@", patch->title, patch->detail];
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

@interface DPOverviewView ()
@property (nonatomic, strong) NSMapTable<DPPatchSwitch *, NSTextField *> *notes;
@property (nonatomic, strong) NSMutableArray<NSArray *> *sections;
@property (nonatomic, strong) NSMutableArray<DPFolderRow *> *folders;
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
        // One folder row stands in for every tweak in it, at the first one's place.
        const DPFolderSpec *folder = patch->group ? DPFolderSpecNamed(patch->group) : NULL;
        if (!folder) {
            add(section, [self rowForPatch:patch]);
            continue;
        }
        if ([folded containsObject:patch->group]) continue;
        [folded addObject:patch->group];
        add(section, [self rowForFolder:folder]);
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
    NSTextField *note = DPHiddenNote();
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [self.notes setObject:note forKey:toggle];
    NSMutableString *search = [NSMutableString new];
    DPAppendSearch(search, patch);

    __weak DPOverviewView *weakSelf = self;
    NSStackView *heading = DPHeading(patch->symbol, patch->tint, @[ DPLabel(patch->title, 13, NSFontWeightRegular, NSColor.labelColor), note ]);
    NSView *row = DPLinkRow(DPRow(heading, DPDisclosure(toggle.withHiddenIcon)), patch->title, ^{
        if (weakSelf.open) weakSelf.open(patch->title, [[DPPageView alloc] initWithPatch:patch]);
    });
    [self.searchText setObject:search forKey:row];
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

    // Searching for anything inside the folder has to find the folder, since its tweaks have no rows of their own.
    NSMutableString *search = [NSMutableString stringWithFormat:@"%@ %@", folder->title, folder->detail];
    for (NSValue *value in members) DPAppendSearch(search, value.pointerValue);

    __weak DPOverviewView *weakSelf = self;
    NSStackView *heading = DPHeading(folder->symbol, folder->tint, @[ DPLabel(folder->title, 13, NSFontWeightRegular, NSColor.labelColor), note ]);
    NSView *row = DPLinkRow(DPRow(heading, DPDisclosure(eye)), folder->title, ^{
        if (weakSelf.open) weakSelf.open(folder->title, [[DPFolderView alloc] initWithFolder:folder]);
    });
    [self.searchText setObject:search forKey:row];
    return row;
}

- (void)syncFolder:(DPFolderRow *)entry {
    // A reason every member shares, like Turn Off AI covering all of them, reads better than a list of names.
    NSString *shared = nil;
    BOOL every = entry.members.count > 0;
    for (NSValue *value in entry.members) {
        DPPatch *member = value.pointerValue;
        NSString *why = DPWhyDisabled(member);
        if (!why || (shared && ![shared isEqualToString:why])) {
            every = NO;
            break;
        }
        shared = why;
    }
    NSMutableArray<NSString *> *shown = [NSMutableArray new];
    for (NSValue *value in entry.members) {
        DPPatch *member = value.pointerValue;
        if (DPShownOn(member)) [shown addObject:member->title];
    }
    NSString *note = every ? [shared stringByReplacingOccurrencesOfString:@"this" withString:@"these"]
                           : [shown componentsJoinedByString:@" · "];
    entry.note.stringValue = note ?: @"";
    entry.note.hidden = !entry.note.stringValue.length;

    NSString *hint = nil;
    if (shown.count) {
        for (NSValue *value in entry.members) {
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
        NSString *summary = DPActiveSummary(toggle.patch);
        NSTextField *note = [self.notes objectForKey:toggle];
        note.stringValue = summary ?: @"";
        note.hidden = !note.stringValue.length;
    }
    for (DPFolderRow *folder in self.folders) [self syncFolder:folder];

    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL anything = NO;
    for (NSArray *section in self.sections) {
        BOOL any = NO;
        NSArray<NSView *> *arranged = ((NSStackView *)((NSView *)[section[2] firstObject]).superview).arrangedSubviews;
        for (NSView *row in section[2]) {
            BOOL visible = row != self.pausedRow || DPPaused || !DPSafeMode;
            NSString *text = visible ? [self.searchText objectForKey:row] : nil;
            for (NSString *word in words) {
                if (!visible) break;
                if (word.length && ![text localizedStandardContainsString:word]) visible = NO;
            }
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
