#import "ProfileColorPicker.h"

static CGFloat DPBackingScale(NSView *view) {
    return MAX(view.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor, 1.0);
}

static CGFloat DPHairline(CGFloat scale) {
    return MIN(1.5 / scale, 1.0);
}

// Dia's ThemeOptionButton ring is 1.5pt, kept on whole device pixels from @2x up so a @1x display doesn't round it to 2pt.
static CGFloat DPRingWidth(CGFloat scale) {
    scale = MAX(scale, 2.0);
    return round(1.5 * scale) / scale;
}

// AppKit turns masksToBounds back on whenever a layer-backed view gets a cornerRadius, which would clip the ring 3pt outside the swatch.
static void DPUnclip(NSView *view) {
    if ([view respondsToSelector:@selector(setClipsToBounds:)]) view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
}

static void DPHueToRGB(CGFloat hue, CGFloat saturation, CGFloat value, CGFloat *red, CGFloat *green, CGFloat *blue) {
    CGFloat sector = hue * 6.0;
    NSInteger index = (NSInteger)floor(sector) % 6;
    CGFloat fraction = sector - floor(sector);
    CGFloat p = value * (1.0 - saturation);
    CGFloat q = value * (1.0 - saturation * fraction);
    CGFloat t = value * (1.0 - saturation * (1.0 - fraction));
    switch (index) {
        case 0: *red = value; *green = t; *blue = p; break;
        case 1: *red = q; *green = value; *blue = p; break;
        case 2: *red = p; *green = value; *blue = t; break;
        case 3: *red = p; *green = q; *blue = value; break;
        case 4: *red = t; *green = p; *blue = value; break;
        default: *red = value; *green = p; *blue = q; break;
    }
}

// Rasterised because NSGradient's relativeCenterPosition: is radial and would draw a bullseye, not macOS' angular hue wheel.
NSImage *DPProfileWheelImage(CGFloat side) {
    CGFloat scale = MAX(NSScreen.mainScreen.backingScaleFactor, 2.0);
    NSInteger pixels = MAX((NSInteger)lround(side * scale), 2);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:pixels
                                                                    pixelsHigh:pixels
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                                                                   bytesPerRow:pixels * 4
                                                                  bitsPerPixel:32];
    if (!rep) return nil;
    uint8_t *bytes = rep.bitmapData;
    CGFloat radius = pixels / 2.0;
    for (NSInteger y = 0; y < pixels; y++) {
        for (NSInteger x = 0; x < pixels; x++) {
            uint8_t *pixel = bytes + (y * pixels + x) * 4;
            CGFloat dx = (x + 0.5) - radius;
            CGFloat dy = (y + 0.5) - radius;
            CGFloat distance = hypot(dx, dy);
            CGFloat coverage = radius - distance;
            if (coverage <= 0.0) {
                pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;
                continue;
            }
            CGFloat hue = atan2(dy, dx) / (2.0 * M_PI);
            if (hue < 0.0) hue += 1.0;
            CGFloat saturation = pow(MIN(distance / radius, 1.0), 0.75);
            CGFloat red = 0, green = 0, blue = 0;
            DPHueToRGB(hue, saturation, 1.0, &red, &green, &blue);
            CGFloat border = 0.25 * (1.0 - DPUnit(coverage));
            red = red * (1.0 - border) + 0.5 * border;
            green = green * (1.0 - border) + 0.5 * border;
            blue = blue * (1.0 - border) + 0.5 * border;
            pixel[0] = (uint8_t)lround(DPUnit(red) * 255.0);
            pixel[1] = (uint8_t)lround(DPUnit(green) * 255.0);
            pixel[2] = (uint8_t)lround(DPUnit(blue) * 255.0);
            pixel[3] = (uint8_t)lround(DPUnit(coverage) * 255.0);
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
    [image addRepresentation:rep];
    return image;
}

static CGFloat DPLuminance(NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!srgb) return 0;
    return 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent;
}

static NSImage *DPSymbol(NSString *name, CGFloat size, NSFontWeight weight) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
}

@interface DPProfileHexField ()
@property (weak) DPProfileColorCircle *circle;
@end

@implementation DPProfileHexField {
    BOOL _skipEndEditing;
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (!DPProfileColorPicker.on || !self.circle) return;
    NSString *canonical = nil;
    if (DPColorFromSixDigitHex(self.stringValue, &canonical)) [self.circle applyHex:canonical fromField:YES];
}

- (void)commit {
    if (!DPProfileColorPicker.on || !self.circle) return;
    NSString *text = [self.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return [self.circle clearColor];
    NSString *canonical = nil;
    if (DPColorFromHex(text, &canonical)) {
        self.stringValue = canonical;
        [self.circle applyHex:canonical fromField:YES];
    } else {
        self.stringValue = DPSavedProfileHexForSpace(self.circle.spaceID) ?: @"";
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (!_skipEndEditing) [self commit];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        [self commit];
        if (textView) textView.string = self.stringValue ?: @"";
    } else if (selector == @selector(cancelOperation:)) {
        NSString *saved = DPSavedProfileHexForSpace(self.circle.spaceID) ?: @"";
        self.stringValue = saved;
        if (textView) textView.string = saved;
    } else {
        return NO;
    }
    _skipEndEditing = YES;
    [self.window makeFirstResponder:nil];
    _skipEndEditing = NO;
    return YES;
}
@end

@implementation DPProfileColorCircle {
    NSView *_neutral, *_fill;
    NSImageView *_plus, *_edit;
    CALayer *_ring;
    NSPopover *_popover;
    DPProfileHexField *_hexField;
    NSButton *_wheelButton, *_clearButton;
    id _mouseMonitor, _keyMonitor, _windowObserver;
    BOOL _panelLinked;
}

- (instancetype)initWithSpaceID:(NSString *)spaceID dimension:(CGFloat)dimension {
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, dimension, dimension)])) return nil;
    _spaceID = [spaceID copy];
    self.wantsLayer = YES;
    DPUnclip(self);

    Class swatch = objc_getClass("_TtC12ColorPalette22NeutralThemeSwatchView");
    _neutral = swatch ? [[swatch alloc] initWithFrame:self.bounds] : [NSView new];
    _neutral.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_neutral];

    _fill = [NSView new];
    _fill.identifier = @"DPProfileColorFill";
    _fill.wantsLayer = YES;
    _fill.layer.masksToBounds = YES;
    _fill.layer.borderColor = [NSColor colorWithWhite:0.5 alpha:0.25].CGColor;
    [self addSubview:_fill];

    _plus = [NSImageView imageViewWithImage:DPSymbol(@"plus", 11, NSFontWeightSemibold)];
    _plus.identifier = @"DPProfileColorPlus";
    _plus.contentTintColor = NSColor.secondaryLabelColor;
    [self addSubview:_plus];

    _edit = [NSImageView imageViewWithImage:DPSymbol(@"pencil", 11, NSFontWeightBold)];
    _edit.identifier = @"DPProfileColorEdit";
    _edit.contentTintColor = NSColor.whiteColor;
    [self addSubview:_edit];

    _ring = [CALayer layer];
    _ring.name = @"DPProfileColorRing";
    _ring.borderColor = NSColor.controlAccentColor.CGColor;
    _ring.opacity = 0;
    [self.layer addSublayer:_ring];

    [self syncFromDefaults];
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)layout {
    [super layout];
    CGFloat side = MIN(NSWidth(self.bounds), NSHeight(self.bounds));
    _neutral.frame = _fill.frame = self.bounds;
    _fill.layer.cornerRadius = side / 2;
    NSRect glyph = NSMakeRect((NSWidth(self.bounds) - 11) / 2, (NSHeight(self.bounds) - 11) / 2, 11, 11);
    _plus.frame = _edit.frame = glyph;
    CGFloat ring = side + 6;
    _ring.bounds = CGRectMake(0, 0, ring, ring);
    _ring.position = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
    _ring.cornerRadius = ring / 2;
    CGFloat scale = DPBackingScale(self);
    _fill.layer.borderWidth = DPHairline(scale);
    _ring.borderWidth = DPRingWidth(scale);
    DPUnclip(self);
}

- (BOOL)suppressesPresets {
    return self.popoverOpen || DPSavedProfileHexForSpace(self.spaceID) != nil;
}

- (void)updateRing {
    NSColor *color = DPColorFromHex(DPSavedProfileHexForSpace(self.spaceID), NULL);
    __block NSColor *accent = NSColor.controlAccentColor;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ accent = NSColor.controlAccentColor; }];
    NSColor *border = color ?: accent;
    BOOL shown = DPProfileColorPicker.on && self.suppressesPresets;
    DPWithoutAnimation(^{
        self->_ring.borderColor = border.CGColor;
        self->_ring.opacity = shown ? 1 : 0;
        self->_ring.transform = shown ? CATransform3DIdentity : CATransform3DMakeScale(0.1, 0.1, 1);
    });
    DPUnclip(self);
}

- (void)syncFromDefaults {
    NSColor *color = DPColorFromHex(DPSavedProfileHexForSpace(self.spaceID), NULL);
    _neutral.hidden = color != nil;
    _fill.hidden = color == nil;
    _fill.layer.backgroundColor = color.CGColor;
    _plus.hidden = color != nil;
    // Dia shows ThemeOptionButton's pencil whenever the swatch is a real colour, so the custom circle does while a colour is set.
    _edit.hidden = color == nil;
    _edit.contentTintColor = DPLuminance(color) > 0.72 ? [NSColor colorWithWhite:0 alpha:0.8] : NSColor.whiteColor;
    if (!_hexField.currentEditor) _hexField.stringValue = DPSavedProfileHexForSpace(self.spaceID) ?: @"";
    _clearButton.hidden = color == nil;
    [self updateRing];
    DPRefreshPresetRings(self.picker);
}

- (void)setPopoverOpen:(BOOL)open {
    if (_popoverOpen == open) return;
    _popoverOpen = open;
    [self updateRing];
    DPRefreshPresetRings(self.picker);
}

- (void)switchToSpaceID:(NSString *)spaceID {
    if ([self.spaceID isEqualToString:spaceID]) return [self syncFromDefaults];
    [self closePopover];
    self.spaceID = spaceID;
    [self syncFromDefaults];
}

- (void)prepareForRemoval {
    [self closePopover];
    _hexField.delegate = nil;
    if (_hexField.currentEditor) [self.window makeFirstResponder:nil];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (_windowObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_windowObserver];
        _windowObserver = nil;
    }
    if (!self.window) return [self closePopover];
    __weak DPProfileColorCircle *weakSelf = self;
    _windowObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
                                                                    object:self.window
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) { [weakSelf closePopover]; }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateRing];
}

- (void)mouseDown:(NSEvent *)event {
    if (!DPProfileColorPicker.on) return;
    if (self.popoverOpen) [self closePopover];
    else [self showPopover];
}

- (NSView *)buildPopoverView {
    _wheelButton = [NSButton buttonWithImage:DPProfileWheelImage(22) target:self action:@selector(openColorPanel)];
    _wheelButton.bordered = NO;
    _wheelButton.imageScaling = NSImageScaleProportionallyUpOrDown;
    _wheelButton.toolTip = @"Color wheel";
    _wheelButton.accessibilityLabel = @"Color wheel";

    _hexField = [DPProfileHexField textFieldWithString:@""];
    _hexField.circle = self;
    _hexField.delegate = _hexField;
    _hexField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    // Left-aligned so the caret NSPopover parks in the empty field doesn't slice through the placeholder.
    _hexField.alignment = NSTextAlignmentLeft;
    _hexField.bezelStyle = NSTextFieldRoundedBezel;
    _hexField.controlSize = NSControlSizeRegular;
    _hexField.focusRingType = NSFocusRingTypeExterior;
    _hexField.placeholderString = @"#RRGGBB";
    _hexField.accessibilityLabel = @"Custom profile color hex";

    _clearButton = [NSButton buttonWithImage:DPSymbol(@"xmark.circle.fill", 16, NSFontWeightRegular) target:self action:@selector(clearColor)];
    _clearButton.bordered = NO;
    _clearButton.bezelStyle = NSBezelStyleInline;
    _clearButton.contentTintColor = NSColor.secondaryLabelColor;
    _clearButton.toolTip = @"Use theme color";
    _clearButton.accessibilityLabel = @"Use theme color";

    NSStackView *row = [NSStackView stackViewWithViews:@[ _wheelButton, _hexField, _clearButton ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    [NSLayoutConstraint activateConstraints:@[
        [_wheelButton.widthAnchor constraintEqualToConstant:22],
        [_wheelButton.heightAnchor constraintEqualToConstant:22],
        [_hexField.widthAnchor constraintEqualToConstant:80],
        [_hexField.heightAnchor constraintEqualToConstant:22],
        [_clearButton.widthAnchor constraintEqualToConstant:16],
        [_clearButton.heightAnchor constraintEqualToConstant:16],
    ]];
    // A horizontal NSStackView leaves edgeInsets out of fittingSize.height, which collapsed the popover to 24pt; a wrapper with pinned insets restores 40pt.
    NSView *wrap = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:9],
        [row.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-9],
        [row.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:11],
        [row.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-11],
    ]];
    return wrap;
}

- (void)showPopover {
    if (!_popover) {
        NSViewController *content = [NSViewController new];
        content.view = [self buildPopoverView];
        _popover = [NSPopover new];
        _popover.contentViewController = content;
        _popover.behavior = NSPopoverBehaviorApplicationDefined;
        _popover.animates = YES;
    }
    [self syncFromDefaults];
    self.popoverOpen = YES;
    [_popover showRelativeToRect:self.bounds ofView:self preferredEdge:NSRectEdgeMaxY];
    [self installMonitors];
}

- (void)closePopover {
    [self removeMonitors];
    if (_popover.isShown) [_popover close];
    if (_panelLinked) {
        NSColorPanel *panel = NSColorPanel.sharedColorPanel;
        panel.target = nil;
        panel.action = NULL;
        [panel orderOut:nil];
        _panelLinked = NO;
    }
    self.popoverOpen = NO;
}

// Local monitors run before the window dispatches mouseDown:, so a click on the circle itself must reach mouseDown: to toggle it shut.
- (NSEvent *)filterMouseDown:(NSEvent *)event {
    NSWindow *window = event.window;
    if (window == _popover.contentViewController.view.window) return event;
    if (window == NSColorPanel.sharedColorPanel) return event;
    if (window == self.window && NSMouseInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds, self.isFlipped)) return event;
    [self closePopover];
    return event;
}

- (void)installMonitors {
    [self removeMonitors];
    __weak DPProfileColorCircle *weakSelf = self;
    _mouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                         handler:^NSEvent *(NSEvent *event) {
        DPProfileColorCircle *circle = weakSelf;
        return circle ? [circle filterMouseDown:event] : event;
    }];
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        DPProfileColorCircle *circle = weakSelf;
        if (!circle || event.keyCode != 53) return event;
        NSResponder *first = NSApp.keyWindow.firstResponder;
        if ([first isKindOfClass:NSTextView.class] && (id)((NSTextView *)first).delegate == (id)circle->_hexField) return event;
        [circle closePopover];
        return nil;
    }];
}

- (void)removeMonitors {
    if (_mouseMonitor) [NSEvent removeMonitor:_mouseMonitor];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    _mouseMonitor = _keyMonitor = nil;
}

- (void)openColorPanel {
    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.showsAlpha = NO;
    panel.continuous = YES;
    panel.color = DPColorFromHex(DPSavedProfileHexForSpace(self.spaceID), NULL) ?: NSColor.whiteColor;
    panel.target = self;
    panel.action = @selector(colorPanelChanged:);
    _panelLinked = YES;
    [panel orderFront:nil];
}

- (void)colorPanelChanged:(NSColorPanel *)panel {
    if (!DPProfileColorPicker.on) return;
    NSString *hex = DPHexFromColor(panel.color);
    if (hex) [self applyHex:hex fromField:NO];
}

- (void)applyHex:(NSString *)canonical fromField:(BOOL)fromField {
    if (!DPProfileColorPicker.on || !self.spaceID) return;
    NSColor *color = DPColorFromHex(canonical, &canonical);
    if (!color) return;
    DPSetProfileHexForSpace(self.spaceID, canonical);
    if (!fromField) _hexField.stringValue = canonical;
    [self syncFromDefaults];
    DPRefreshProfileColors();
}

- (void)clearColor {
    if (!DPProfileColorPicker.on || !self.spaceID) return;
    DPSetProfileHexForSpace(self.spaceID, nil);
    [self syncFromDefaults];
    [self closePopover];
    DPRefreshProfileColors();
}
@end
