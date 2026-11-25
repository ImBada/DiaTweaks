#import "LaunchFlags.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"

@interface DPLaunchFlagsBox : NSView
@end

@implementation DPLaunchFlagsBox
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 6;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1;
    self.layer.masksToBounds = YES;
    return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = NSColor.textBackgroundColor.CGColor;
        self.layer.borderColor = NSColor.separatorColor.CGColor;
    }];
}
@end

static NSTextView *DPLaunchFlagsEditor(NSFont *font, id<NSTextViewDelegate> delegate) {
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 76)];
    tv.drawsBackground = tv.richText = tv.importsGraphics = tv.usesFindBar = NO;
    tv.automaticDashSubstitutionEnabled = tv.automaticQuoteSubstitutionEnabled = tv.automaticSpellingCorrectionEnabled = NO;
    tv.continuousSpellCheckingEnabled = tv.grammarCheckingEnabled = tv.automaticTextReplacementEnabled = NO;
    tv.automaticLinkDetectionEnabled = tv.smartInsertDeleteEnabled = tv.horizontallyResizable = NO;
    tv.allowsUndo = tv.verticallyResizable = YES;
    tv.font = font;
    tv.textColor = tv.insertionPointColor = NSColor.labelColor;
    tv.textContainerInset = NSMakeSize(4, 6);
    tv.minSize = NSMakeSize(0, 76);
    tv.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    tv.autoresizingMask = NSViewWidthSizable;
    tv.textContainer.containerSize = NSMakeSize(320, CGFLOAT_MAX);
    tv.textContainer.widthTracksTextView = YES;
    tv.accessibilityLabel = @"Chromium launch flags";
    tv.delegate = delegate;
    return tv;
}

@interface DPLaunchFlagsRow : NSStackView <NSTextViewDelegate>
@property (nonatomic) BOOL enabled, edited;
@property (nonatomic, strong) DPLaunchFlagsBox *box;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSTextField *placeholder, *status;
@property (nonatomic, strong) NSButton *relaunch;
@end

@implementation DPLaunchFlagsRow

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.spacing = 6;
    _enabled = YES;

    NSFont *mono = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    NSTextField *label = DPLabel(@"Flags", 13, NSFontWeightRegular, NSColor.labelColor);

    _box = [DPLaunchFlagsBox new];
    _box.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholder = [NSTextField labelWithString:@"--force-renderer-accessibility=complete"];
    _placeholder.font = mono;
    _placeholder.textColor = NSColor.placeholderTextColor;
    _placeholder.lineBreakMode = NSLineBreakByTruncatingTail;
    _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [_box addSubview:_placeholder];

    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = _textView = DPLaunchFlagsEditor(mono, self);
    [_box addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [_box.heightAnchor constraintEqualToConstant:76],
        [_placeholder.leadingAnchor constraintEqualToAnchor:_box.leadingAnchor constant:9],
        [_placeholder.trailingAnchor constraintLessThanOrEqualToAnchor:_box.trailingAnchor constant:-9],
        [_placeholder.topAnchor constraintEqualToAnchor:_box.topAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:_box.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_box.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_box.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_box.bottomAnchor],
    ]];

    _status = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [_status setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_status setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _relaunch = [NSButton buttonWithTitle:@"Relaunch" target:self action:@selector(relaunchDia:)];
    _relaunch.controlSize = NSControlSizeSmall;
    [_relaunch setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *footer = [NSStackView stackViewWithViews:@[ _status, _relaunch ]];
    footer.spacing = 8;
    footer.alignment = NSLayoutAttributeCenterY;
    footer.detachesHiddenViews = YES;

    [self setViews:@[ label, _box, footer ] inGravity:NSStackViewGravityTop];
    [_box.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [footer.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(reloadFromDefaults) name:DPPatchesDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(flushEdits) name:NSApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:nil];
    [self reloadFromDefaults];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _textView.delegate = nil;
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _textView.editable = _textView.selectable = enabled;
    if (!enabled && self.window.firstResponder == _textView) [self.window makeFirstResponder:nil];
    _box.alphaValue = enabled ? 1 : 0.5;
    [self refreshStatus];
}

- (void)reloadFromDefaults {
    NSString *saved = DPLaunchFlagsSavedText();
    if (!_edited && ![_textView.string isEqualToString:saved]) _textView.string = saved;
    [self refreshStatus];
}

- (void)refreshStatus {
    NSString *text = _textView.string ?: @"";
    _placeholder.hidden = text.length > 0;
    BOOL unclosed = NO;
    NSArray<NSString *> *ignored = nil;
    NSArray<NSString *> *flags = DPParseLaunchFlags(text, &ignored, &unclosed);
    NSArray<NSString *> *launched = DPLaunchFlagsLaunched();
    BOOL pending = _enabled && !unclosed && ![flags isEqual:launched];

    NSString *message = @"One flag per line, or separated by spaces. Lines starting with # are ignored.";
    NSColor *color = NSColor.secondaryLabelColor;
    if (unclosed) {
        message = @"Unclosed quote.";
        color = NSColor.systemRedColor;
    } else if (ignored.count) {
        message = [NSString stringWithFormat:@"Ignored (must start with --): %@", [ignored componentsJoinedByString:@", "]];
        color = NSColor.systemRedColor;
    } else if (pending) {
        message = @"Relaunch Dia to apply these flags.";
    } else if (_enabled && launched.count) {
        message = @"Active in this session.";
    }
    _status.stringValue = message;
    _status.textColor = color;
    _relaunch.hidden = !pending;
    _relaunch.enabled = pending;
}

- (void)flushEdits {
    if (!_enabled) return;
    _edited = NO;
    NSString *text = _textView.string ?: @"";
    if (![text isEqualToString:DPLaunchFlagsSavedText()]) DPLaunchFlagsSaveText(text);
    [self refreshStatus];
}

- (void)windowWillClose:(NSNotification *)note {
    if (note.object == self.window) [self flushEdits];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (!newWindow) [self flushEdits];
    [super viewWillMoveToWindow:newWindow];
}

- (void)textDidChange:(NSNotification *)notification {
    _edited = YES;
    [self refreshStatus];
}

- (void)textDidEndEditing:(NSNotification *)notification {
    [self flushEdits];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command == @selector(insertTab:)) return [textView.window selectNextKeyView:textView], YES;
    if (command == @selector(insertBacktab:)) return [textView.window selectPreviousKeyView:textView], YES;
    return NO;
}

- (void)relaunchDia:(id)sender {
    [self.window endEditingFor:nil];
    [self flushEdits];
    DPHandOffAndQuit(@[ @"apply" ]);
}

@end

NSArray<NSView *> *DPLaunchFlagsRows(void) { return @[ [DPLaunchFlagsRow new] ]; }
