#import "Patches/ShowAddressField/ShowAddressField.m"

static BOOL gCallbackHovered;
static BOOL gCallbackIncidental;
static int gCallbackCalls;

static void DPTestHoverHandler(bool hovered, bool incidental, void *context __attribute__((swift_context))) __attribute__((swiftcall)) {
    gCallbackHovered = hovered;
    gCallbackIncidental = incidental;
    gCallbackCalls++;
    (void)context;
}

@interface _TtC5ARCUI16ViewHoverTracker : NSObject {
@public
    BOOL isHovered;
    __weak NSView *view;
}
@end
@implementation _TtC5ARCUI16ViewHoverTracker
- (void)mouseEntered:(NSEvent *)event {}
- (void)mouseMoved:(NSEvent *)event {}
- (void)mouseExited:(NSEvent *)event {}
@end

@interface DPFakeDelayedTracker : NSObject {
@public
    BOOL isHoverActive;
    BOOL isIncidentalHover;
    void *onUpdate[2];
}
@end
@implementation DPFakeDelayedTracker
@end

@interface _TtC13NavigationBar16AssistantBarView : NSView {
@public
    DPFakeDelayedTracker *hoverTracker;
}
@end
@implementation _TtC13NavigationBar16AssistantBarView
@end

@interface DPTestWindow : NSWindow
@property BOOL fakeKey;
@property NSPoint fakeMouse;
@end
@implementation DPTestWindow
- (BOOL)isVisible { return YES; }
- (BOOL)isKeyWindow { return self.fakeKey; }
- (NSPoint)mouseLocationOutsideOfEventStream { return self.fakeMouse; }
@end

@interface DPFlippedPane : NSView
@end
@implementation DPFlippedPane
- (BOOL)isFlipped { return YES; }
@end

static int failures;

static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 800)
                                                               styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];
        window.fakeKey = YES;

        NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 760)];
        NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 720, 1000, 40)];
        _TtC13NavigationBar16AssistantBarView *field = [[_TtC13NavigationBar16AssistantBarView alloc] initWithFrame:NSMakeRect(100, 4, 800, 32)];
        NSView *button = [[NSView alloc] initWithFrame:NSMakeRect(380, 4, 40, 24)];
        [field addSubview:button];
        _TtC5ARCUI16ViewHoverTracker *tracker = [_TtC5ARCUI16ViewHoverTracker new];
        tracker->view = field;
        DPFakeDelayedTracker *delayed = [DPFakeDelayedTracker new];
        delayed->onUpdate[0] = (void *)DPTestHoverHandler;
        field->hoverTracker = delayed;
        [field addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                              owner:tracker
                                                           userInfo:nil]];
        [bar addSubview:field];
        [pane addSubview:bar];
        [window.contentView addSubview:pane];

        window.fakeMouse = NSMakePoint(500, 740);
        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        check("turning on highlights field", delayed->isHoverActive && tracker->isHovered && !DPVerifyShowAddressField(&DPShowAddressField));

        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        check("turning off while pointer is over visible field keeps highlight",
              DPPointerOver(field) && delayed->isHoverActive && !DPVerifyShowAddressField(&DPShowAddressField));

        window.fakeMouse = NSMakePoint(500, 400);
        DPApplyShowAddressField(&DPShowAddressField);
        check("turning off with pointer away clears highlight",
              !DPPointerOver(field) && !delayed->isHoverActive && !tracker->isHovered && !gCallbackHovered && !DPVerifyShowAddressField(&DPShowAddressField));

        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        bar.frame = NSMakeRect(0, 760, 1000, 40);
        window.fakeMouse = NSMakePoint(500, 780);
        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        check("lifted bar above pane does not match pointer inside window above pane",
              !DPPointerOver(field) && !delayed->isHoverActive && !DPVerifyShowAddressField(&DPShowAddressField));

        pane.frame = NSMakeRect(0, 0, 1000, 800);
        bar.frame = NSMakeRect(0, 800, 1000, 40);
        bar.alphaValue = 0;
        window.fakeMouse = NSMakePoint(500, 820);
        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        bar.frame = NSMakeRect(0, 760, 1000, 40);
        bar.alphaValue = 1;
        check("lifted hidden bar above window clears highlight before bar lowers",
              !DPPointerOver(field) && !delayed->isHoverActive && !tracker->isHovered && !DPVerifyShowAddressField(&DPShowAddressField));

        bar.alphaValue = 0;
        window.fakeMouse = NSMakePoint(500, 780);
        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        bar.alphaValue = 1;
        check("transparent bar in place does not keep highlight", !delayed->isHoverActive);

        NSView *cover = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 800)];
        [window.contentView addSubview:cover];
        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        check("covered field does not match pointer", !DPPointerOver(field) && !delayed->isHoverActive);
        [cover removeFromSuperview];

        window.fakeKey = NO;
        DPShowAddressField.on = YES;
        DPApplyShowAddressField(&DPShowAddressField);
        DPShowAddressField.on = NO;
        DPApplyShowAddressField(&DPShowAddressField);
        check("non-key window clears highlight even at field coordinates", !DPPointerOver(field) && !delayed->isHoverActive);

        DPFlippedPane *flippedPane = [[DPFlippedPane alloc] initWithFrame:NSMakeRect(0, 0, 1000, 800)];
        [pane removeFromSuperview];
        bar.frame = NSMakeRect(0, -40, 1000, 40);
        bar.alphaValue = 1;
        [flippedPane addSubview:bar];
        [window.contentView addSubview:flippedPane];
        window.fakeKey = YES;
        window.fakeMouse = NSMakePoint(500, 820);
        check("flipped pane lifted bar does not match pointer above window", !DPPointerOver(field));
        bar.frame = NSMakeRect(0, 0, 1000, 40);
        window.fakeMouse = NSMakePoint(500, 780);
        check("flipped pane visible bar matches pointer over subview of field", DPPointerOver(field));

        gCallbackIncidental = YES;
        DPSetHover(field, YES);
        check("hover callback ran with incidental=false", gCallbackCalls > 0 && !gCallbackIncidental);

        // Regression: invisible/minimized window restores hover state on apply-off and layout-off.
        DPTestWindow *hiddenWin = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100)
                                                                  styleMask:NSWindowStyleMaskBorderless
                                                                    backing:NSBackingStoreBuffered
                                                                      defer:NO];
        hiddenWin.fakeKey = NO;
        hiddenWin.fakeMouse = NSMakePoint(0, 0);
        _TtC13NavigationBar16AssistantBarView *hiddenField = [[_TtC13NavigationBar16AssistantBarView alloc] initWithFrame:NSMakeRect(10, 10, 300, 32)];
        _TtC5ARCUI16ViewHoverTracker *hiddenTracker = [_TtC5ARCUI16ViewHoverTracker new];
        hiddenTracker->view = hiddenField;
        DPFakeDelayedTracker *hiddenDelayed = [DPFakeDelayedTracker new];
        hiddenDelayed->onUpdate[0] = (void *)DPTestHoverHandler;
        hiddenField->hoverTracker = hiddenDelayed;
        [hiddenField addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                                  options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                                    owner:hiddenTracker
                                                                 userInfo:nil]];
        [hiddenWin.contentView addSubview:hiddenField];
        DPInstallShowAddressField();
        DPShowAddressField.on = YES;
        [hiddenField layout];
        check("layout forces hover on when enabled", hiddenDelayed->isHoverActive && DPGet(hiddenField, &DPForcedKey) != nil);
        DPShowAddressField.on = NO;
        [hiddenField layout];
        check("layout restores hover once when disabled and clears state",
              !hiddenDelayed->isHoverActive && !hiddenTracker->isHovered && DPGet(hiddenField, &DPForcedKey) == nil);

        // Regression: missing ivars never crash.
        NSView *plainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        check("missing hoverTracker ivar does not crash", !DPShowsHover(plainView));
        DPSetHover(plainView, YES);
        check("missing view ivar on tracker does not crash", !DPKeepsHover([NSObject new]));
    }
    if (failures) return 1;
    puts("PASS: showAddressField hover checks");
    return 0;
}
