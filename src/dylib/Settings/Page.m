#import "Settings.h"

static char DPChoicePatchKey;

static NSArray<NSView *> *DPRowsOf(DPPatch *patch) {
    NSArray<NSView *> *rows = patch->rows ? patch->rows() : @[];
    return patch->shortcut ? [@[ DPShortcutRow(patch) ] arrayByAddingObjectsFromArray:rows] : rows;
}

@implementation DPPageView {
    DPPatch *_patch;
    NSMutableArray<DPPatchSwitch *> *_switches;
    NSMutableArray<NSPopUpButton *> *_pickers;
    NSTextField *_note;
    NSArray<NSView *> *_rows;
    NSMutableArray<NSView *> *_optionChoices;
    NSMutableArray<NSArray *> *_gated, *_cards;
}

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _switches = [NSMutableArray new];
    _pickers = [NSMutableArray new];
    _optionChoices = [NSMutableArray new];
    _gated = [NSMutableArray new];
    _cards = [NSMutableArray new];
    NSMutableSet<NSString *> *gatedTitles = [NSMutableSet new];
    _note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);

    DPPreviewView *preview = [[DPPreviewView alloc] initWithKey:patch->key];
    [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:10.0 / 16].active = YES;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:preview, [self headingGroup], nil];

    NSString *const unavailable = @"Not Available in This Version";
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"Options"];
    NSMutableDictionary<NSString *, NSMutableArray<NSView *> *> *groups = [NSMutableDictionary dictionaryWithObject:[NSMutableArray new] forKey:@"Options"];
    void (^add)(NSString *, NSView *) = ^(NSString *title, NSView *row) {
        if (!groups[title]) {
            [titles addObject:title];
            groups[title] = [NSMutableArray new];
        }
        [groups[title] addObject:row];
    };
    if (patch->choices) add(@"Options", [self choiceRowFor:patch]);
    DPForEachOption(patch, ^(DPPatch *option) {
        NSString *title = option->unavailable ? unavailable : option->section ?: @"Options";
        NSMutableArray<NSView *> *lines = [NSMutableArray arrayWithObjects:DPLabel(option->title, 13, NSFontWeightRegular, NSColor.labelColor),
                                           DPLabel(option->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), nil];
        if (option->experimental) [lines addObject:DPExperimentalBadge()];
        if (option->unavailable) [lines addObject:DPLabel(DPWhyDisabled(option), 11, NSFontWeightRegular, NSColor.secondaryLabelColor)];
        NSView *leading = DPColumn(lines, 2);
        if (DPRequired(option) != patch) {
            NSView *spacer = [NSView new];
            [spacer.widthAnchor constraintEqualToConstant:16].active = YES;
            NSStackView *indented = [NSStackView stackViewWithViews:@[ spacer, leading ]];
            indented.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            indented.spacing = 0;
            leading = indented;
        }
        NSView *optionRow = DPRow(leading, [self switchFor:option]);
        if (option->experimental) {
            [self->_gated addObject:@[ optionRow, [NSValue valueWithPointer:option] ]];
            [gatedTitles addObject:title];
        }
        add(title, optionRow);
        NSArray<NSView *> *optionRows = DPRowsOf(option);
        if (option->choices || optionRows.count) {
            NSMutableArray<NSView *> *under = [NSMutableArray arrayWithCapacity:optionRows.count + (option->choices != NULL)];
            if (option->choices) [under addObject:[self choiceRowFor:option]];
            for (NSView *view in optionRows) [under addObject:DPFullRow(view)];
            for (NSView *row in under) {
                DPSet(row, &DPChoicePatchKey, [NSValue valueWithPointer:option]);
                add(title, row);
                [self->_optionChoices addObject:row];
            }
        }
    });
    _rows = DPRowsOf(patch);
    NSMutableArray<NSView *> *cards = [NSMutableArray new];
    for (NSView *view in _rows) {
        if ([view isMemberOfClass:DPFillView.class]) [cards addObject:view];
        else if ([view.identifier isEqual:DPLeadingOption]) [groups[@"Options"] insertObject:DPFullRow(view) atIndex:0];
        else add(view.identifier ?: @"Options", DPFullRow(view));
    }
    if ([titles containsObject:unavailable]) {
        [titles removeObject:unavailable];
        [titles addObject:unavailable];
    }
    NSMutableDictionary<NSString *, NSNumber *> *ranks = [NSMutableDictionary new];
    for (NSString *title in titles) {
        if ([title isEqual:@"Options"]) continue;
        for (NSUInteger i = 0; i < DPPatchCount; i++) {
            DPPatch *option = DPPatches[i];
            if (!DPRequired(option) || ![title isEqual:option->section ?: @"Options"]) continue;
            NSNumber *rank = ranks[title];
            if (!rank || DPDeclaredOrder(option) < rank.intValue) ranks[title] = @(DPDeclaredOrder(option));
        }
    }
    [titles sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqual:@"Options"] != [b isEqual:@"Options"]) return [a isEqual:@"Options"] ? NSOrderedAscending : NSOrderedDescending;
        return [ranks[a] ?: @(NSIntegerMax) compare:ranks[b] ?: @(NSIntegerMax)];
    }];
    for (NSString *title in titles) {
        if (!groups[title].count) continue;
        NSView *header = DPHeader(title), *group = DPGroup(groups[title]);
        [views addObjectsFromArray:@[ header, group ]];
        if ([gatedTitles containsObject:title]) [_cards addObject:@[ header, group ]];
    }
    for (NSView *card in cards) {
        if (card.identifier.length) [views addObject:DPHeader(card.identifier)];
        [views addObject:card];
    }
    [views addObject:[self footerGroup]];

    DPFillStack(self, views);
    [self sync];
    return self;
}

- (NSView *)headingGroup {
    NSMutableArray<NSView *> *headingText = [@[
        DPLabel(_patch->title, 13, NSFontWeightSemibold, NSColor.labelColor),
        DPLabel(_patch->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor),
    ] mutableCopy];
    if (_patch->experimental) [headingText addObject:DPExperimentalBadge()];
    if (_patch->hint) {
        NSView *gap = [NSView new];
        [gap.heightAnchor constraintEqualToConstant:5].active = YES;
        [headingText addObjectsFromArray:@[gap, DPLabel(_patch->hint, 11, NSFontWeightRegular, NSColor.secondaryLabelColor)]];
    }
    [headingText addObject:_note];
    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(_patch->symbol, DPTintColor(_patch->tint)),
        DPColumn(headingText, 2),
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;
    return DPGroup(@[DPRow(heading, [self switchFor:_patch])]);
}

- (NSView *)footerGroup {
    NSTextField *how = DPLabel([@"diatweaks enable " stringByAppendingString:_patch->key], 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    how.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    how.selectable = YES;
    NSView *howRow = DPRow(DPColumn(@[DPLabel(@"Turn on from Terminal", 13, NSFontWeightRegular, NSColor.labelColor), how], 2), [NSStackView new]);
    NSURL *wiki = DPWikiURL(_patch);
    if (!wiki) return DPGroup(@[ howRow ]);
    NSView *wikiRow = DPLinkRow(DPRow(DPLabel(@"Read more on the wiki", 13, NSFontWeightRegular, NSColor.labelColor),
                                      DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                                @"Read more on the wiki", ^{ [NSWorkspace.sharedWorkspace openURL:wiki]; });
    return DPGroup(@[wikiRow, howRow]);
}

- (NSView *)switchFor:(DPPatch *)patch {
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [_switches addObject:toggle];
    return toggle.withHiddenIcon;
}

static void DPSelectChoice(NSPopUpButton *picker, DPPatch *patch) {
    id choice = DPChoice(patch) ?: NSNull.null;
    // A menu item without a representedObject is the nil choice, so it still has to be pickable.
    for (NSMenuItem *item in picker.menu.itemArray)
        if ([(item.representedObject ?: NSNull.null) isEqual:choice]) return [picker selectItem:item];
}

- (NSView *)choiceRowFor:(DPPatch *)patch {
    NSMenu *menu = patch->choices();
    NSPopUpButton *picker = [NSPopUpButton new];
    picker.menu = menu;
    picker.controlSize = NSControlSizeSmall;
    picker.target = self;
    picker.action = @selector(choose:);
    DPSet(picker, &DPChoicePatchKey, [NSValue valueWithPointer:patch]);
    DPSelectChoice(picker, patch);
    [_pickers addObject:picker];
    return DPRow(DPLabel(menu.title, 13, NSFontWeightRegular, NSColor.labelColor), picker);
}

- (void)choose:(NSPopUpButton *)picker {
    DPPatch *patch = [DPGet(picker, &DPChoicePatchKey) pointerValue] ?: _patch;
    id choice = picker.selectedItem.representedObject;
    if (![choice isKindOfClass:NSString.class]) return DPSelectChoice(picker, patch);
    DPSetChoice(patch, choice);
}

static void DPSetRowControlsEnabled(NSView *view, BOOL enabled) {
    if (!view || ([view isKindOfClass:NSTextField.class] && !((NSTextField *)view).editable)) return;
    if ([view respondsToSelector:@selector(setEnabled:)]) return [(id)view setEnabled:enabled];
    for (NSView *sub in view.subviews) DPSetRowControlsEnabled(sub, enabled);
}

- (void)sync {
    BOOL running = !DPSafeMode && !DPPaused && !DPPausedAtLaunch;
    for (DPPatchSwitch *toggle in _switches) [toggle sync];
    for (NSPopUpButton *picker in _pickers) {
        DPPatch *patch = [DPGet(picker, &DPChoicePatchKey) pointerValue] ?: _patch;
        picker.enabled = running && !DPWhyDisabled(patch);
        DPSelectChoice(picker, patch);
    }
    for (NSView *row in _rows)
        if (![row isMemberOfClass:DPFillView.class]) DPSetRowControlsEnabled(row, _patch->on && running);
    for (NSArray *gated in _gated) ((NSView *)gated[0]).hidden = !DPExperimentalShown([gated[1] pointerValue]);
    // Fade in after the group has grown, or the row rides over the one above.
    NSMutableArray<NSView *> *appeared = nil;
    for (NSView *row in _optionChoices) {
        DPPatch *option = [DPGet(row, &DPChoicePatchKey) pointerValue];
        if (!option) continue;
        DPSetRowControlsEnabled(row, option->on && !DPWhyDisabled(option) && running);
        BOOL shown = DPShownOn(option);
        if (row.hidden != shown) continue;
        NSStackView *stack = [row.superview isKindOfClass:NSStackView.class] ? (NSStackView *)row.superview : nil;
        NSArray<NSView *> *rows = stack.arrangedSubviews;
        NSUInteger i = [rows indexOfObject:row];
        NSArray<NSView *> *views = i != NSNotFound && i > 0 ? @[row, rows[i - 1]] : @[row];
        // Hidden inside an animation, AppKit fades it out while it moves, which leaves a ghost behind.
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0;
            context.allowsImplicitAnimation = NO;
            for (NSView *view in views) {
                view.hidden = !shown;
                if (shown) view.alphaValue = 0;
            }
        }];
        if (shown) {
            if (!appeared) appeared = [NSMutableArray new];
            [appeared addObjectsFromArray:views];
        }
    }
    for (NSArray<NSView *> *card in _cards) card[0].hidden = !DPTidyGroup(card[1]);
    if (appeared.count)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.2;
                for (NSView *view in appeared) if (view.window && !view.hidden) view.animator.alphaValue = 1;
            }];
        });
    _note.stringValue = DPWhyDisabled(_patch) ?: @"";
    _note.hidden = !_note.stringValue.length;
}
@end
