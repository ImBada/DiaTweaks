#import "Patches/SidebarAddressBar/Popover.m"
DPPatch DPSidebarAddressBar;
void DPSidebarInstallSuggestionOverlay(void) {}
@interface AnchoredFixture : NSView
@property BOOL nativeEditorVisible;
@end
@implementation AnchoredFixture
- (BOOL)isFlipped { return YES; }
@end
@interface InitialPopupFixture : AnchoredFixture
@property NSRect initialWindowFrame;
@end
@implementation InitialPopupFixture
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) self.initialWindowFrame = self.frame;
}
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    Class native = objc_allocateClassPair(InitialPopupFixture.class, DPDiaPopover, 0);
    objc_registerClassPair(native);
    DPSidebarInstallPopover();
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    window.contentView = [[AnchoredFixture alloc] initWithFrame:NSMakeRect(0,0,1200,800)];
    NSView *anchor = [[AnchoredFixture alloc] initWithFrame:NSMakeRect(6,54,210,36)];
    [window.contentView addSubview:anchor];
    NSRect nativeFrame = NSMakeRect(300,-16,880,130);
    NSView *page = [[native alloc] initWithFrame:nativeFrame];
    page.identifier = @"native-identifier";
    page.wantsLayer = YES;
    DPSidebarAddressBar.on = YES;
    DPSidebarRequestPopover(anchor);
    [window.contentView addSubview:page];
    NSCAssert([page.identifier isEqual:DPSidebarPopoverIdentifier], @"mark the native sidebar popup before Command bar handles it");
    NSCAssert(!page.hidden && NSWidth(page.frame) > NSWidth(anchor.frame), @"keep the native popup visible with room for its shadow");
    NSCAssert(NSContainsRect(window.contentView.bounds,NSInsetRect(page.frame,10,10)), @"stay within the browser window");
    NSCAssert(fabs(NSMinY(page.frame)+10-NSMinY(anchor.frame)) < 0.1, @"align the input with the sidebar row");
    NSCAssert(NSEqualRects(((InitialPopupFixture *)page).initialWindowFrame,page.frame), @"native opening must start at the anchored frame, before attachment animation");
    NSCAssert(page.layer.hidden, @"the native editor must not paint during initial layout");
    [page.layer addAnimation:[CABasicAnimation animationWithKeyPath:@"position"] forKey:@"dia-opening-position"];
    [page.layer addAnimation:[CABasicAnimation animationWithKeyPath:@"opacity"] forKey:@"dia-opening-opacity"];
    NSCAssert(![page.layer animationForKey:@"dia-opening-position"] && ![page.layer animationForKey:@"dia-opening-opacity"], @"sidebar editor opens without a motion or opacity transition");
    page.frame = nativeFrame;
    NSCAssert(NSMinX(page.frame)+10 == NSMinX(anchor.frame) && NSWidth(page.frame) == NSWidth(anchor.frame) + 20, @"native relayout must preserve sidebar positioning");
    page.frameSize = NSMakeSize(880,130);
    NSCAssert(NSWidth(page.frame) == NSWidth(anchor.frame) + 20, @"native size-only writes cannot restore toolbar width");
    page.frameOrigin = NSMakePoint(500,-16);
    NSCAssert(NSMinX(page.frame)+10 == NSMinX(anchor.frame), @"native origin updates must not move the sidebar popup to the toolbar");
    anchor.frame = NSMakeRect(6,54,300,36);
    page.frame = nativeFrame;
    NSCAssert(NSWidth(page.frame) == 320, @"adapt popup width to sidebar width");
    NSView *keyboardPopup = [[native alloc] initWithFrame:nativeFrame];
    [window.contentView addSubview:keyboardPopup];
    NSCAssert(keyboardPopup.identifier == nil && NSEqualRects(keyboardPopup.frame,nativeFrame), @"consume only the sidebar request; keyboard popups retain native geometry");
    page.layer.hidden = NO;
    NSCAssert(page.layer.hidden, @"AppKit cannot expose the layer during the initial layout pass");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    NSCAssert(!page.layer.hidden, @"the editor must become visible after its first anchored layout");
    [page removeFromSuperview];
    NSCAssert([page.identifier isEqual:@"native-identifier"], @"restore native identity on dismissal");
    DPSidebarAddressBar.on = NO;
    page.frame = nativeFrame;
    [window.contentView addSubview:page];
    NSCAssert(NSEqualRects(page.frame,nativeFrame), @"disabled patch must not change native popover geometry");
    puts("PASS: sidebar-native popup anchoring, resize, keyboard independence, dismissal identity, and disabled state");
} }
