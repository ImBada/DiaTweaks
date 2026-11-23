#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileEmoji;

static NSString *const DPEmojisKey = @"profileEmojis";
static const CGFloat DPSidebarEmojiSize = 13.5, DPSidebarEmojiWidth = 16, DPSidebarDotWidth = 6, DPSidebarGap = 10;
static NSUserDefaults *DPEmojiDefaults;
static NSHashTable<NSViewController *> *DPProfilePanes;
static char DPLabelKey, DPRowKey;

static NSString *DPEmoji(NSString *spaceID) {
    return DPProfileEmoji.on && spaceID ? [DPEmojiDefaults dictionaryForKey:DPEmojisKey][spaceID] : nil;
}

static NSString *DPSpaceIDOf(NSView *view, NSDictionary *views) {
    for (id key in views) if (views[key] == view) return [key description];
    return nil;
}

static BOOL DPAnyEmoji(NSDictionary *views, NSDictionary *emojis) {
    for (id key in views) if (emojis[[key description]]) return YES;
    return NO;
}

static BOOL DPAnySidebarEmoji(NSView *switcher) {
    if (!DPProfileEmoji.on || !switcher) return NO;
    NSDictionary *emojis = [DPEmojiDefaults dictionaryForKey:DPEmojisKey];
    return emojis.count && DPAnyEmoji(DPSwiftValue(switcher, @"itemViews"), emojis);
}

static void DPShowEmoji(NSView *host, NSView *dot, NSString *emoji, CGFloat size, CGFloat alpha) {
    NSTextField *label = DPGet(host, &DPLabelKey);
    if (!emoji) {
        if (!label) return;
        if (dot.hidden) dot.hidden = NO;
        [label removeFromSuperview];
        DPSet(host, &DPLabelKey, nil);
        return;
    }
    if (!dot.hidden) dot.hidden = YES;
    BOOL resized = !label;
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.alignment = NSTextAlignmentCenter;
        [host addSubview:label];
        DPSet(host, &DPLabelKey, label);
    }
    if (![label.stringValue isEqual:emoji]) {
        label.stringValue = emoji;
        resized = YES;
    }
    if (fabs(label.font.pointSize - size) > 0.01) {
        label.font = [NSFont systemFontOfSize:size];
        resized = YES;
    }
    if (fabs(label.alphaValue - alpha) > 0.001) label.alphaValue = alpha;
    if (resized) [label sizeToFit];
    NSRect target = (NSRect){ { round(NSMidX(host.bounds) - label.frame.size.width / 2), round(NSMidY(host.bounds) - label.frame.size.height / 2) }, label.frame.size };
    if (!NSEqualRects(label.frame, target)) label.frame = target;
}

static void DPShowSidebarItem(NSView *item) {
    NSTextField *existing = DPGet(item, &DPLabelKey);
    if (!DPProfileEmoji.on && !existing) return;
    NSString *emoji = DPEmoji(DPSpaceIDOf(item, DPSwiftValue(item.superview, @"itemViews")));
    BOOL any = emoji || DPAnySidebarEmoji(item.superview);
    if (!existing && !any) return;
    BOOL selected = [DPSwiftValue(item, @"isSelected") boolValue];
    NSView *dot = DPSwiftValue(item, @"$__lazy_storage_$_dotView");
    if (dot && !emoji) {
        NSPoint origin = NSMakePoint(round(NSMidX(item.bounds) - NSWidth(dot.frame) / 2), NSMinY(dot.frame));
        if (!NSEqualPoints(dot.frame.origin, origin)) [dot setFrameOrigin:origin];
    }
    DPShowEmoji(item, dot, emoji, DPSidebarEmojiSize, selected ? 1 : 0.45);
}

static CGFloat DPSidebarItemWidth(NSView *item, NSDictionary *views, NSDictionary *emojis) {
    NSString *spaceID = DPSpaceIDOf(item, views);
    return (spaceID && emojis[spaceID] ? DPSidebarEmojiWidth : DPSidebarDotWidth) + DPSidebarGap;
}

static void DPSidebarItem_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (!DPProfileEmoji.on || NSWidth(frame) <= 0 || NSWidth(frame) >= DPSidebarDotWidth + DPSidebarGap)
        return DPCallOriginal(DPSidebarItem_setFrame, self, frame);
    NSDictionary *emojis = [DPEmojiDefaults dictionaryForKey:DPEmojisKey];
    if (!emojis.count) return DPCallOriginal(DPSidebarItem_setFrame, self, frame);
    NSView *switcher = self.superview;
    NSDictionary *views = DPSwiftValue(switcher, @"itemViews");
    if (DPAnyEmoji(views, emojis)) {
        CGFloat middle = NSMidX(switcher.bounds);
        NSInteger index = lround((NSMinX(frame) - (middle - views.count * NSWidth(frame) / 2)) / NSWidth(frame));
        NSMutableArray<NSView *> *row = [NSMutableArray arrayWithCapacity:views.count + 1];
        for (NSView *item in views.allValues) if (item != self) [row addObject:item];
        [row sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
            CGFloat left = NSMidX(a.frame), right = NSMidX(b.frame);
            if (left < right) return NSOrderedAscending;
            return left > right ? NSOrderedDescending : NSOrderedSame;
        }];
        [row insertObject:self atIndex:MIN(MAX(index, 0), (NSInteger)row.count)];
        CGFloat total = 0, x = 0;
        for (NSView *item in row) total += DPSidebarItemWidth(item, views, emojis);
        for (NSView *item in row) {
            if (item == self) break;
            x += DPSidebarItemWidth(item, views, emojis);
        }
        frame = NSMakeRect(round(middle - total / 2 + x), NSMinY(frame), DPSidebarItemWidth(self, views, emojis), NSHeight(frame));
    }
    DPCallOriginal(DPSidebarItem_setFrame, self, frame);
}

static void DPSidebarItem_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarItem_layout, self);
    DPShowSidebarItem(self);
}

static void DPSidebarItem_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarItem_updateLayer, self);
    NSTextField *label = DPGet(self, &DPLabelKey);
    if (!DPProfileEmoji.on && !label) return;
    NSString *emoji = DPEmoji(DPSpaceIDOf(self, DPSwiftValue(self.superview, @"itemViews")));
    if ((emoji != nil) != (label != nil)) {
        __weak NSView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.needsLayout = YES; });
        return;
    }
    if (!label) return;
    CGFloat alpha = [DPSwiftValue(self, @"isSelected") boolValue] ? 1 : 0.45;
    if (fabs(label.alphaValue - alpha) > 0.001) label.alphaValue = alpha;
}

static void DPTopDot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTopDot_layout, self);
    NSView *label = DPGet(self, &DPLabelKey);
    if (!DPProfileEmoji.on && !label) return;
    NSView *indicator = self.superview, *dot = nil;
    for (NSView *sub in self.subviews) if (sub != label) { dot = sub; break; }
    NSString *spaceID = DPSpaceIDOf(self, DPSwiftValue(indicator, @"dotViews"));
    BOOL focused = [[DPSwiftValue(indicator, @"focusedSpaceID") description] isEqual:spaceID];
    DPShowEmoji(self, dot, DPEmoji(spaceID), 8, focused ? 1 : 0.45);
}

static void DPCollectEmojiViews(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectEmojiViews(sub, cls, out);
}

static void DPRefresh(void) {
    for (NSString *name in @[ @DPDiaSpaceSwitcher, @DPDiaSpaceSwitcherItem, @DPDiaPageIndicatorDot ]) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        NSMutableArray<NSView *> *views = [NSMutableArray new];
        for (NSWindow *window in NSApp.windows) DPCollectEmojiViews(window.contentView, cls, views);
        for (NSView *view in views) view.needsLayout = YES;
    }
}

@interface DPEmojiField : NSTextField <NSTextFieldDelegate>
@property(copy) NSString *spaceID;
@end

@implementation DPEmojiField
- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became) dispatch_async(dispatch_get_main_queue(), ^{ [NSApp orderFrontCharacterPalette:self]; });
    return became;
}

- (void)controlTextDidChange:(NSNotification *)note {
    __block NSString *last = @"";
    [self.stringValue enumerateSubstringsInRange:NSMakeRange(0, self.stringValue.length) options:NSStringEnumerationByComposedCharacterSequences
                                      usingBlock:^(NSString *character, NSRange _, NSRange __, BOOL *___) { last = character; }];
    last = [last stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self.stringValue isEqual:last]) self.stringValue = last;
    NSMutableDictionary *emoji = [[DPEmojiDefaults dictionaryForKey:DPEmojisKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    emoji[self.spaceID] = last.length ? last : nil;
    [DPEmojiDefaults setObject:emoji forKey:DPEmojisKey];
    DPRefresh();
}
@end

static void DPAddEmojiRow(NSViewController *pane) {
    NSView *group = DPFindView(pane.view, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSettingsFormGroup); });
    NSStackView *rows = (NSStackView *)DPSubview(group, "NSStackView");
    NSTextField *title = (NSTextField *)DPFindView(rows.arrangedSubviews.firstObject, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    NSString *spaceID = [DPSwiftValue(pane, @"spaceID") description];
    if (!rows || !title || !spaceID || DPGet(pane, &DPRowKey)) return;

    NSTextField *label = [NSTextField labelWithString:@"Emoji"];
    label.font = title.font;
    label.textColor = title.textColor;
    DPEmojiField *field = [DPEmojiField textFieldWithString:[DPEmojiDefaults dictionaryForKey:DPEmojisKey][spaceID] ?: @""];
    field.spaceID = spaceID;
    field.delegate = field;
    field.alignment = NSTextAlignmentCenter;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.placeholderString = @"None";
    NSView *row = [NSView new];
    for (NSView *view in @[ label, field ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:view];
    }
    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    [rows addArrangedSubview:line];
    [rows addArrangedSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:42], [row.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
        [line.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor], [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.widthAnchor constraintEqualToConstant:64],
    ]];
    DPSet(pane, &DPRowKey, @[ line, row ]);
}

static void DPRemoveEmojiRow(NSViewController *pane) {
    for (NSView *view in DPGet(pane, &DPRowKey)) [view removeFromSuperview];
    DPSet(pane, &DPRowKey, nil);
}

static void DPApplyProfileEmoji(DPPatch *patch) {
    for (NSViewController *pane in DPProfilePanes.allObjects) {
        if (patch->on) DPAddEmojiRow(pane);
        else DPRemoveEmojiRow(pane);
    }
    DPRefresh();
}

static void DPProfilePane_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPProfilePane_viewDidLoad, self);
    [DPProfilePanes addObject:self];
    if (DPProfileEmoji.on) DPAddEmojiRow(self);
}

static void DPInstallProfileEmoji(void) {
    DPEmojiDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPProfilePanes = [NSHashTable weakObjectsHashTable];
    DPHookClass(objc_getClass(DPDiaSpaceSwitcherItem), @selector(setFrame:), (IMP)DPSidebarItem_setFrame);
    DPHook(DPDiaSpaceSwitcherItem, @selector(layout), (IMP)DPSidebarItem_layout);
    DPHook(DPDiaSpaceSwitcherItem, @selector(updateLayer), (IMP)DPSidebarItem_updateLayer);
    DPHook(DPDiaPageIndicatorDot, @selector(layout), (IMP)DPTopDot_layout);
    DPHook(DPDiaProfilePane, @selector(viewDidLoad), (IMP)DPProfilePane_viewDidLoad);
}

DP_PATCH(DPProfileEmoji) {
    .key = @"profileEmoji",
    .order = 84,
    .defaultOn = YES,
    .title = @"Profile Emoji",
    .detail = @"Show an emoji in place of each profile’s dot in the profile switcher. Choose them in Settings › Profiles.",
    .symbol = @"emoji.face.grinning.inverse face.smiling.inverse",
    .tint = @"systemRedColor",
    .section = @"Profiles",
    .classes = DPClasses(DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem, DPDiaPageIndicatorDot, DPDiaProfilePane, DPDiaSettingsFormGroup),
    .install = DPInstallProfileEmoji,
    .apply = DPApplyProfileEmoji,
};
