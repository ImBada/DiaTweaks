#import "ProfileColorPicker.h"

@implementation DPProfileColorWell {
    id _windowCloseObserver;
}

- (void)stopWatchingWindow {
    if (_windowCloseObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_windowCloseObserver];
        _windowCloseObserver = nil;
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [self stopWatchingWindow];
    if (!newWindow && self.isActive) [self deactivate];
    [super viewWillMoveToWindow:newWindow];
    if (newWindow) {
        __weak DPProfileColorWell *weakSelf = self;
        _windowCloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
                                                                               object:newWindow
                                                                                queue:nil
                                                                           usingBlock:^(NSNotification *note) {
            DPProfileColorWell *well = weakSelf;
            if (well.isActive) [well deactivate];
        }];
    }
}

// Avoid calling [self deactivate] in dealloc: AppKit/NSColorPanel may form weak references to self during deactivation.
- (void)dealloc {
    [self stopWatchingWindow];
}
@end

@interface DPProfileHexField ()
@property (weak) DPProfileColorRow *row;
@end

@implementation DPProfileHexField {
    BOOL _skipNextEndEditing;
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (!DPProfileColorPicker.on || !self.row || self.row.suppressCommit) return;
    NSString *canonical = nil;
    if (DPColorFromSixDigitHex(self.stringValue, &canonical)) [self.row applyHex:canonical fromField:YES];
}

- (void)commitText {
    if (!DPProfileColorPicker.on || !self.row || self.row.suppressCommit) return;
    NSString *trimmed = [self.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return [self.row clearColor];
    NSString *canonical = nil;
    if (DPColorFromHex(trimmed, &canonical)) {
        self.stringValue = canonical;
        [self.row applyHex:canonical fromField:YES];
    } else {
        self.stringValue = DPSavedProfileHexForSpace(self.row.spaceID) ?: @"";
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (_skipNextEndEditing) return;
    [self commitText];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        [self commitText];
        if (textView) textView.string = self.stringValue ?: @"";
        _skipNextEndEditing = YES;
        [self.window makeFirstResponder:nil];
        _skipNextEndEditing = NO;
        return YES;
    }
    if (selector == @selector(cancelOperation:)) {
        NSString *saved = DPSavedProfileHexForSpace(self.row.spaceID) ?: @"";
        self.stringValue = saved;
        if (textView) textView.string = saved;
        _skipNextEndEditing = YES;
        [self.window makeFirstResponder:nil];
        _skipNextEndEditing = NO;
        return YES;
    }
    return NO;
}
@end

@implementation DPProfileColorRow {
    BOOL _syncing;
}

static NSColor *DPPlaceholderWellColor(void) {
    return [NSColor colorWithSRGBRed:0.78 green:0.78 blue:0.80 alpha:1.0];
}

- (instancetype)initWithSpaceID:(NSString *)spaceID font:(NSFont *)font textColor:(NSColor *)textColor {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _spaceID = [spaceID copy];

    NSTextField *label = [NSTextField labelWithString:@"Custom Color"];
    label.font = font;
    label.textColor = textColor;

    _well = [[DPProfileColorWell alloc] initWithFrame:NSMakeRect(0, 0, 52, 24)];
    _well.colorWellStyle = NSColorWellStyleExpanded;
    _well.supportsAlpha = NO;
    _well.continuous = YES;
    _well.target = self;
    _well.action = @selector(wellChanged:);
    _well.accessibilityLabel = @"Custom profile color";

    _hexField = [DPProfileHexField textFieldWithString:@""];
    _hexField.row = self;
    _hexField.delegate = _hexField;
    _hexField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _hexField.alignment = NSTextAlignmentCenter;
    _hexField.bezelStyle = NSTextFieldRoundedBezel;
    _hexField.placeholderString = @"#RRGGBB";
    _hexField.accessibilityLabel = @"Custom profile color hex";

    NSImage *clearIcon = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Clear custom color"];
    _clearButton = [NSButton buttonWithImage:clearIcon target:self action:@selector(clearColor)];
    _clearButton.bordered = NO;
    _clearButton.bezelStyle = NSBezelStyleInline;
    _clearButton.contentTintColor = NSColor.secondaryLabelColor;
    _clearButton.toolTip = @"Use preset color";
    _clearButton.accessibilityLabel = @"Clear custom color";

    NSStackView *controls = [NSStackView stackViewWithViews:@[ _well, _hexField, _clearButton ]];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.alignment = NSLayoutAttributeCenterY;
    controls.spacing = 6;

    for (NSView *v in @[ label, controls ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:42],
        [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [controls.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_well.widthAnchor constraintEqualToConstant:52],
        [_well.heightAnchor constraintEqualToConstant:24],
        [_hexField.widthAnchor constraintEqualToConstant:86],
        [_clearButton.widthAnchor constraintEqualToConstant:18],
        [_clearButton.heightAnchor constraintEqualToConstant:18],
    ]];
    [self syncFromDefaults:YES];
    return self;
}

- (void)syncFromDefaults:(BOOL)forceField {
    _syncing = YES;
    NSString *hex = DPSavedProfileHexForSpace(self.spaceID);
    NSColor *color = DPColorFromHex(hex, NULL);
    if (forceField && !color && self.well.isActive) [self.well deactivate];
    self.well.color = color ?: DPPlaceholderWellColor();
    if (forceField || !self.hexField.currentEditor) self.hexField.stringValue = hex ?: @"";
    self.clearButton.hidden = (color == nil);
    _syncing = NO;
}

- (void)switchToSpaceID:(NSString *)spaceID {
    if ([self.spaceID isEqualToString:spaceID]) return [self syncFromDefaults:NO];
    if (self.well.isActive) [self.well deactivate];
    self.suppressCommit = YES;
    if (self.hexField.currentEditor) [self.window makeFirstResponder:nil];
    self.spaceID = spaceID;
    self.suppressCommit = NO;
    [self syncFromDefaults:YES];
}

- (void)prepareForRemoval {
    self.suppressCommit = YES;
    if (self.well.isActive) [self.well deactivate];
    self.hexField.delegate = nil;
    if (self.hexField.currentEditor) [self.window makeFirstResponder:nil];
}

- (void)wellChanged:(id)sender {
    if (_syncing || !DPProfileColorPicker.on || self.suppressCommit) return;
    NSString *hex = DPHexFromColor(self.well.color);
    if (hex) [self applyHex:hex fromField:NO];
}

- (void)applyHex:(NSString *)canonical fromField:(BOOL)fromField {
    if (!DPProfileColorPicker.on || self.suppressCommit) return;
    NSColor *color = DPColorFromHex(canonical, &canonical);
    if (!color || !self.spaceID) return;
    DPSetProfileHexForSpace(self.spaceID, canonical);
    _syncing = YES;
    if (!fromField) self.hexField.stringValue = canonical;
    self.well.color = color;
    self.clearButton.hidden = NO;
    _syncing = NO;
    DPRefreshProfileColors();
}

- (void)clearColor {
    if (!DPProfileColorPicker.on || self.suppressCommit) return;
    if (self.well.isActive) [self.well deactivate];
    if (self.spaceID) DPSetProfileHexForSpace(self.spaceID, nil);
    [self syncFromDefaults:YES];
    DPRefreshProfileColors();
}
@end
