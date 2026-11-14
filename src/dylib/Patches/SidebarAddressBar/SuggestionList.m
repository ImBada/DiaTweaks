#import "Editor.h"

@interface DPAddressSuggestionItem : NSStackView
@property (copy) void (^activate)(void);
@end
@implementation DPAddressSuggestionItem
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityButtonRole; }
- (BOOL)accessibilityPerformPress { if (self.activate) self.activate(); return YES; }
@end

@implementation DPAddressSuggestionList
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTracking) [self removeTrackingArea:self.hoverTracking];
    self.hoverTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseMoved |
            NSTrackingMouseEnteredAndExited | NSTrackingEnabledDuringMouseDrag
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverTracking];
}
- (NSInteger)indexAtPoint:(NSPoint)point {
    for (NSUInteger index = 0; index < self.arrangedSubviews.count; index++)
        if (NSPointInRect(point, self.arrangedSubviews[index].frame)) return (NSInteger)index;
    return -1;
}
- (NSView *)hitTest:(NSPoint)point { return [super hitTest:point] ? self : nil; }
- (void)mouseDown:(NSEvent *)event {
    NSInteger index = [self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0 && self.activateIndex) self.activateIndex(index);
}
- (void)rightMouseDown:(NSEvent *)event {}
- (void)mouseMoved:(NSEvent *)event {
    if (self.hoverChanged) self.hoverChanged([self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]]);
}
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseEntered:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseExited:(NSEvent *)event { if (self.hoverChanged) self.hoverChanged(-1); }
@end

@implementation DPSidebarAddressRow (SuggestionList)
- (void)highlightSuggestion:(NSInteger)index {
    self.selectedSuggestion = index;
    self.hoveredSuggestion = -1;
    [self refreshSuggestionHighlight];
}
- (void)refreshSuggestionHighlight {
    NSInteger index = self.hoveredSuggestion >= 0 ? self.hoveredSuggestion : self.selectedSuggestion;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        NSArray<NSView *> *items = self.suggestions.arrangedSubviews;
        for (NSInteger row = 0; row < (NSInteger)items.count; row++)
            items[(NSUInteger)row].layer.backgroundColor = row == index ?
                [NSColor.controlAccentColor colorWithAlphaComponent:0.17].CGColor : nil;
        [CATransaction commit];
    }];
}
- (void)dismissSuggestionList {
    if (!self.suggestions) return;
    DPSidebarUnshieldDropdown(self.suggestions);
    [self.suggestions removeFromSuperview];
    self.suggestions = nil;
    [self setFrameSize:NSMakeSize(NSWidth(self.frame), 36)];
    DPSidebarUpdateHover(self, NO);
}
- (void)positionSuggestions {
    if (!self.suggestions || !self.window) return;
    CGFloat height = [self preferredHeight];
    NSRect frame = NSMakeRect(0, 36, NSWidth(self.bounds), height - 36);
    BOOL changed = !NSEqualRects(self.suggestions.frame, frame);
    if (NSHeight(self.frame) != height) [self setFrameSize:NSMakeSize(NSWidth(self.frame), height)];
    if (changed) self.suggestions.frame = frame;
    // The expanded row overlays tabs without moving them. One view owns the
    // background, border, corners, input and results; there is no popup seam.
    if (self.superview.subviews.lastObject != self) [self.superview addSubview:self positioned:NSWindowAbove relativeTo:nil];
    if (changed) DPSidebarShieldDropdown(self.suggestions, self.window);
}
- (void)renderSuggestions {
    if (!self.suggestionURLs.count || !self.window) { [self dismissSuggestionList]; return; }
    if (!self.suggestions) {
        DPAddressSuggestionList *list = [[DPAddressSuggestionList alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(self.bounds), 1)];
        __weak DPSidebarAddressRow *weakRow = self;
        list.hoverChanged = ^(NSInteger index) {
            DPSidebarAddressRow *row = weakRow;
            if (row.hoveredSuggestion == index) return;
            row.hoveredSuggestion = index;
            [row refreshSuggestionHighlight];
        };
        list.activateIndex = ^(NSInteger index) { [weakRow submitSuggestionAtIndex:index]; };
        list.orientation = NSUserInterfaceLayoutOrientationVertical;
        list.alignment = NSLayoutAttributeLeading;
        list.distribution = NSStackViewDistributionFillEqually;
        list.spacing = 2;
        list.edgeInsets = NSEdgeInsetsMake(2, 6, 6, 6);
        list.wantsLayer = YES;
        list.accessibilityLabel = @"Address suggestions";
        self.suggestions = list;
        [self addSubview:list];
    }
    for (NSView *item in self.suggestions.arrangedSubviews.copy) [item removeFromSuperview];
    for (NSUInteger index = 0; index < self.suggestionURLs.count; index++) {
        NSTextField *title = [NSTextField labelWithString:self.suggestionURLs[index]];
        title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        title.textColor = NSColor.labelColor;
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        title.maximumNumberOfLines = 1;
        [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSMutableArray<NSView *> *content = [NSMutableArray array];
        if (index < self.nativeSuggestionIcons.count) {
            NSImageView *icon = [NSImageView imageViewWithImage:DPSidebarSuggestionIcon(self.nativeSuggestionIcons[index])];
            icon.imageScaling = NSImageScaleProportionallyDown;
            icon.contentTintColor = NSColor.secondaryLabelColor;
            [icon.widthAnchor constraintEqualToConstant:14].active = YES;
            [icon.heightAnchor constraintEqualToConstant:14].active = YES;
            [content addObject:icon];
        }
        [content addObject:title];
        DPAddressSuggestionItem *entry = [DPAddressSuggestionItem stackViewWithViews:content];
        __weak DPSidebarAddressRow *weakRow = self;
        entry.activate = ^{ [weakRow submitSuggestionAtIndex:(NSInteger)index]; };
        entry.accessibilityLabel = title.stringValue;
        entry.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        entry.alignment = NSLayoutAttributeCenterY;
        entry.spacing = 8;
        entry.edgeInsets = NSEdgeInsetsMake(0, 8, 0, 8);
        entry.wantsLayer = YES;
        entry.layer.cornerRadius = 6;
        [self.suggestions addArrangedSubview:entry];
        [entry.widthAnchor constraintEqualToAnchor:self.suggestions.widthAnchor constant:-12].active = YES;
    }
    [self positionSuggestions];
    [self.suggestions layoutSubtreeIfNeeded];
    [self refreshSuggestionHighlight];
    DPSidebarUpdateHover(self, NO);
}
@end
