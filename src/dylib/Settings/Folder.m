#import "Settings.h"

static const DPFolderSpec DPFolders[] = {
    { @"pinnedTabs", @"Pinned Tabs",
      @"Pin tabs with a shortcut, fold pinned tabs away, unload pinned splits, and choose how their close buttons, borders and hover cards behave.",
      @"pin.fill", @"systemTealColor", @"Sidebar & Tab Bar" },
    { @"aiPrompts", @"Hide AI Prompts & Buttons",
      @"Hide individual Chat, Skills and trial buttons or prompts while keeping the rest of Dia’s AI on.",
      @"eye.slash.fill", @"systemPurpleColor", @"AI" },
    { @"passwordManagers", @"Password Managers",
      @"Let 1Password, Bitwarden, Proton Pass and Apple Passwords connect to a patched Dia.",
      @"key.fill", @"systemGreenColor", @"Passwords" },
};

const DPFolderSpec *DPFolderSpecNamed(NSString *key) {
    if (!key) return NULL;
    for (NSUInteger i = 0; i < sizeof DPFolders / sizeof *DPFolders; i++)
        if ([DPFolders[i].key isEqualToString:key]) return &DPFolders[i];
    return NULL;
}

@implementation DPFolderView {
    const DPFolderSpec *_folder;
    NSMutableArray<NSValue *> *_patches;
    NSMutableArray<DPPatchSwitch *> *_switches;
    NSMutableArray<NSTextField *> *_notes;
    NSMutableArray<NSView *> *_rows;
    NSView *_group;
}

- (instancetype)initWithFolder:(const DPFolderSpec *)folder {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _folder = folder;
    _patches = [NSMutableArray new];
    _switches = [NSMutableArray new];
    _notes = [NSMutableArray new];
    _rows = [NSMutableArray new];

    for (NSValue *value in DPFolderMembers(folder->key)) {
        DPPatch *member = value.pointerValue;
        NSTextField *note = DPHiddenNote();
        NSMutableArray<NSView *> *lines = [NSMutableArray arrayWithObjects:DPLabel(member->title, 13, NSFontWeightRegular, NSColor.labelColor),
                                           DPLabel(member->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), nil];
        if (member->experimental) [lines addObject:DPExperimentalBadge()];
        [lines addObject:note];
        DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:member];
        __weak DPFolderView *weakSelf = self;
        [_rows addObject:DPLinkRow(DPRow(DPHeading(member->symbol, member->tint, lines), DPDisclosure(toggle.withHiddenIcon)), member->title, ^{
            if (weakSelf.open) weakSelf.open(member->title, [[DPPageView alloc] initWithPatch:member]);
        })];
        [_patches addObject:value];
        [_switches addObject:toggle];
        [_notes addObject:note];
    }
    _group = DPGroup(_rows);
    DPFillStack(self, @[ DPLabel(folder->detail, 12, NSFontWeightRegular, NSColor.secondaryLabelColor), _group ]);
    [self sync];
    return self;
}

- (void)sync {
    for (NSUInteger i = 0; i < _switches.count; i++) {
        [_switches[i] sync];
        DPPatch *patch = _patches[i].pointerValue;
        NSString *summary = DPActiveSummary(patch);
        NSTextField *note = _notes[i];
        note.stringValue = summary ?: @"";
        note.hidden = !note.stringValue.length;
        _rows[i].hidden = !DPExperimentalShown(patch);
    }
    DPTidyGroup(_group);
}
@end
