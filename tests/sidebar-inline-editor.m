#import "Patches/SidebarAddressBar/Editor.h"

DPPatch DPSidebarAddressBar;
extern DPPatch DPSidebarDefaultEditor;

// Models Dia's text view requesting focus while it updates suggestions.
@interface InlineSidebarHost : NSView @end
@implementation InlineSidebarHost
- (BOOL)isFlipped { return YES; }
@end

@interface InlineNativeText : NSTextView @end
@implementation InlineNativeText
- (void)insertText:(id)text replacementRange:(NSRange)range {
    [super insertText:text replacementRange:range];
    [self.window makeFirstResponder:self];
}
@end

@interface InlineNativeResults : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property NSArray<NSString *> *titles;
@property NSTableView *table;
@property NSInteger submissions;
@end
@implementation InlineNativeResults
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return self.titles.count; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return [NSTextField labelWithString:self.titles[(NSUInteger)row]];
}
- (void)textDidChange:(NSNotification *)note {
    NSString *query = [(NSTextView *)note.object string];
    self.titles = query.length ? @[[query stringByAppendingString:@" history"], [query stringByAppendingString:@" chat"]] : @[];
    [self.table reloadData];
}
- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)command {
    if (command == @selector(insertNewline:)) { self.submissions++; return YES; }
    return command == @selector(cancelOperation:);
}
@end

static NSView *NativeView(const char *name, NSRect frame) {
    Class cls = objc_getClass(name);
    if (!cls) { cls = objc_allocateClassPair(NSView.class, name, 0); objc_registerClassPair(cls); }
    return [[cls alloc] initWithFrame:frame];
}

static NSData *AddressPrefixPixels(NSButton *button) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:220 pixelsHigh:36
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSColor.clearColor setFill]; NSRectFillUsingOperation(NSMakeRect(0,0,220,36), NSCompositingOperationCopy);
    [button drawRect:button.bounds];
    [NSGraphicsContext restoreGraphicsState];
    NSMutableData *prefix = [NSMutableData data];
    for (NSInteger y=0;y<36;y++) [prefix appendBytes:bitmap.bitmapData + y*bitmap.bytesPerRow length:40*4];
    return prefix;
}

@interface InlineCommandOverlay : NSView
@property NSView *shade, *windowBlur;
@end
@implementation InlineCommandOverlay @end

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,500,600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.contentView = [[InlineSidebarHost alloc] initWithFrame:NSMakeRect(0,0,500,600)];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (window.windowNumber <= 0) {
        fputs("SKIP: mouse dispatch requires WindowServer access; run outside the restricted sandbox.\n",stderr);
        return 77;
    }
    BOOL originalMouseMoved = window.acceptsMouseMovedEvents;
    NSView *composer = NativeView(DPDiaCommandBar, NSMakeRect(0,0,300,80));
    NSButton *attachment = [NSButton buttonWithTitle:@"" target:nil action:nil];
    attachment.accessibilityLabel = @"Add a tab or file";
    [composer addSubview:attachment];
    [composer addSubview:[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,250,24)]];
    [window.contentView addSubview:composer];
    NSView *page = NativeView(DPDiaNewTabPage, NSMakeRect(0,0,500,600));
    NSView *bar = NativeView(DPDiaCommandBar, NSMakeRect(0,0,300,180));
    NSView *input = NativeView(DPDiaCommandBarText, NSMakeRect(0,140,300,24));
    NSView *suggestions = NativeView(DPDiaCommandBarSuggestions, NSMakeRect(0,0,300,130));
    InlineNativeText *native = [[InlineNativeText alloc] initWithFrame:input.bounds];
    InlineNativeResults *results = [InlineNativeResults new];
    NSTableView *table = [[NSTableView alloc] initWithFrame:suggestions.bounds];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"result"]];
    table.dataSource = results;
    table.delegate = results;
    results.table = table;
    native.delegate = results;
    [input addSubview:native]; [bar addSubview:input]; [bar addSubview:suggestions];
    [suggestions addSubview:table]; [page addSubview:bar]; [window.contentView addSubview:page];
    page.hidden = YES;
    NSView *pin = [[NSView alloc] initWithFrame:NSMakeRect(8,116,220,220)];
    pin.toolTip = @"Pinned tab underneath";
    NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:pin.bounds
        options:NSTrackingActiveAlways | NSTrackingMouseEnteredAndExited owner:pin userInfo:nil];
    [pin addTrackingArea:tracking];
    [window.contentView addSubview:pin];
    DPSidebarAddressRow *row = [[DPSidebarAddressRow alloc] initWithFrame:NSMakeRect(8,80,220,36)];
    [window.contentView addSubview:row];
    row.address.title = @"dashboard.skydo.com";
    [row layoutAddressBefore:220];
    NSData *widePrefix = AddressPrefixPixels(row.address);
    [row layoutAddressBefore:110];
    NSCAssert([widePrefix isEqual:AddressPrefixPixels(row.address)],
        @"revealing actions must not move, scale or tighten the leading address glyphs");
    DPSidebarAddressBar.on = YES;
    DPSidebarDefaultEditor.on = NO;
    DPSidebarInstallInlineFocus();
    [row openEditor:nil];
    NSCAssert(row.inlineEditor && row.nativeSuggestionEditor == native, @"blank tabs must reuse their address input, never a chat composer");
    NSCAssert(window.firstResponder == row.inlineEditor.currentEditor, @"native startup must preserve inline focus");
    NSTextView *editor = (NSTextView *)row.inlineEditor.currentEditor;
    [editor insertText:@"complete query" replacementRange:NSMakeRange(0, editor.string.length)];
    [row controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:row.inlineEditor]];
    [row refreshNativeSuggestions];
    NSCAssert([editor.string isEqual:@"complete query"] && window.firstResponder == editor, @"native updates cannot take any typed characters");
    NSCAssert([native.string isEqual:editor.string], @"the native query must stay in sync");
    NSCAssert(row.suggestionURLs.count == 2 && row.suggestions.superview == row, @"the custom dropdown must render native results");
    NSCAssert(row.selectedSuggestion == 0 && row.suggestions.arrangedSubviews[0].layer.backgroundColor,
        @"native results must highlight the first suggestion by default");
    NSRect coveredScreen = [window convertRectToScreen:[row.suggestions convertRect:row.suggestions.bounds toView:nil]];
    NSCAssert(DPSidebarSuggestionsContainScreenPoint(NSMakePoint(NSMidX(coveredScreen),NSMidY(coveredScreen))),
        @"native tooltip suppression must cover the actual expanded suggestion surface");
    NSCAssert(NSHeight(row.frame) > 36 && NSMinY(row.inlineEditor.frame) == 9,
        @"expanding results must not move the input or its baseline");
    NSCAssert([row hitTest:NSMakePoint(NSMidX(row.frame), NSMinY(row.frame) + 50)] == row.suggestions,
        @"the expanded surface must capture input above the covered tabs");
    NSImage *whiteIcon = [NSImage imageWithSize:NSMakeSize(14,14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.whiteColor setFill]; NSRectFill(NSInsetRect(rect,3,3)); return YES;
    }];
    NSCAssert(DPSidebarSuggestionIcon(whiteIcon).isTemplate,
        @"a white-only native favicon must adapt to the current appearance");
    NSView *mountedPanel = row.suggestions;
    [row updateNativeSuggestionsWithQuery:@"complete query updated"];
    NSCAssert(row.suggestions == mountedPanel && mountedPanel.superview == row,
        @"typing must preserve the expanded surface until native results refresh");
    [row refreshNativeSuggestions];
    NSCAssert(![pin.trackingAreas containsObject:tracking] && !pin.toolTip, @"covered tabs must lose tracking and tooltips");
    NSView *hiddenShell = [[NSView alloc] initWithFrame:row.frame];
    hiddenShell.wantsLayer = YES;
    [window.contentView addSubview:hiddenShell positioned:NSWindowAbove relativeTo:nil];
    DPSidebarHideSuggestionSurface(hiddenShell, YES);
    NSCAssert([window.contentView hitTest:[window.contentView convertPoint:NSMakePoint(100,130) toView:window.contentView.superview]] == row.suggestions,
        @"the hidden native shell must pass real pointer hits to the custom list");
    DPSidebarHideSuggestionSurface(hiddenShell, NO);
    [hiddenShell removeFromSuperview];
    NSView *second = row.suggestions.arrangedSubviews[1];
    NSPoint pointer = [row.suggestions convertPoint:NSMakePoint(NSMidX(second.frame),NSMidY(second.frame)) toView:nil];
    NSEvent *move = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:pointer modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
        eventNumber:1 clickCount:0 pressure:0];
    [NSApp sendEvent:move];
    NSCAssert(row.hoveredSuggestion == 1 && second.layer.backgroundColor, @"pointer movement must highlight the complete result row");
    [row highlightSuggestion:0];
    NSCAssert(row.selectedSuggestion == 0 && row.suggestions.arrangedSubviews[0].layer.backgroundColor,
        @"keyboard highlighting uses the same complete row bounds");
    for (NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        row.appearance = [NSAppearance appearanceNamed:appearance];
        [row renderSuggestions];
        [row.effectiveAppearance performAsCurrentDrawingAppearance:^{
            NSCAssert(CGColorEqualToColor(row.layer.backgroundColor, DPSidebarEditorFill().CGColor), @"input and results must share a surface in both appearances");
        }];
        NSCAssert(row.suggestions.superview == row && !row.suggestions.layer.backgroundColor,
            @"results must be children of the single address surface, without a second background");
    }
    NSCAssert(window.acceptsMouseMovedEvents, @"the embedded list must receive window mouse movement");
    __block BOOL nativeSawClick = NO;
    id nativeClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp
        handler:^NSEvent *(NSEvent *event) { nativeSawClick = YES; return event; }];
    NSTextView *current = (NSTextView *)row.inlineEditor.currentEditor;
    current.selectedRange = NSMakeRange(0,current.string.length);
    NSPoint rightEdge = [row convertPoint:NSMakePoint(NSWidth(row.bounds)-3,18) toView:nil];
    for (NSNumber *type in @[@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]) {
        [NSApp sendEvent:[NSEvent mouseEventWithType:type.integerValue location:rightEdge modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
            eventNumber:2 clickCount:1 pressure:1]];
    }
    NSCAssert(row.inlineEditor && current.selectedRange.length == 0 && current.selectedRange.location == current.string.length,
        @"a right-edge click must keep editing and move the selected URL caret to the end");
    NSView *first = row.suggestions.arrangedSubviews[0];
    NSPoint firstPoint = [row.suggestions convertPoint:NSMakePoint(NSMidX(first.frame),NSMidY(first.frame)) toView:nil];
    [NSApp sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:firstPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
        eventNumber:3 clickCount:1 pressure:1]];
    NSCAssert(results.submissions == 1 && !nativeSawClick,
        @"a real dispatched mouse click must activate the native result before hidden-editor outside-click monitors");
    [NSEvent removeMonitor:nativeClickMonitor];
    DPSidebarDefaultEditor.on = YES;
    DPSidebarDefaultEditor.apply(&DPSidebarDefaultEditor);
    NSCAssert(!row.inlineEditor && !row.suggestions, @"switching modes must end custom editing immediately");
    NSCAssert([pin.trackingAreas containsObject:tracking] && [pin.toolTip isEqual:@"Pinned tab underneath"], @"dismissal must restore covered controls");
    NSCAssert(window.acceptsMouseMovedEvents == originalMouseMoved, @"dismissal must restore the host mouse-movement setting");
    NSCAssert(bar.alphaValue == 1, @"native visibility must be restored after editing");
    DPSidebarDefaultEditor.on = NO;
    [bar removeFromSuperview];
    [row openEditor:nil];
    row.startingSuggestionSession = YES;
    Class overlayClass = objc_allocateClassPair(InlineCommandOverlay.class, "DPCommandBarOverlay", 0);
    objc_registerClassPair(overlayClass);
    InlineCommandOverlay *overlay = [[overlayClass alloc] initWithFrame:window.contentView.bounds];
    overlay.wantsLayer = YES;
    [window.contentView addSubview:overlay];
    NSView *panel = NativeView(DPDiaAssistantPanel, bar.frame);
    panel.wantsLayer = YES;
    [panel addSubview:bar];
    DPSidebarInstallSuggestionOverlay();
    [overlay addSubview:panel];
    NSCAssert(row.nativeSuggestionEditor == native && row.nativeOverlay == overlay,
        @"follow the actual native input when upstream reparents it into its command overlay");
    overlay.shade = [NSView new]; overlay.shade.wantsLayer = YES;
    overlay.windowBlur = [NSView new]; overlay.windowBlur.wantsLayer = YES;
    [window.contentView addSubview:overlay.shade]; [window.contentView addSubview:overlay.windowBlur];
    DPSidebarQuietSuggestionOverlay(row);
    [row finishStartingSuggestionSession];
    NSCAssert(row.inlineEditor.currentEditor == window.firstResponder && overlay.layer.hidden && panel.layer.hidden,
        @"native overlay startup must preserve the inline field and hide its borrowed surfaces");
    NSCAssert(overlay.shade.alphaValue == 0 && overlay.shade.layer.hidden && overlay.windowBlur.layer.hidden,
        @"also hide shade and blur created after the native input attachment");
    [row finishInlineEditing];
    NSCAssert(overlay.shade.alphaValue == 1 && !overlay.shade.layer.hidden && !panel.layer.hidden,
        @"dismissal restores all borrowed native overlay surfaces");
    [window orderOut:nil];
    puts("PASS: blank-tab native reuse, focus isolation, full queries, native results, pointer and keyboard highlights, tracking restoration, appearances, and live mode switching");
} }
