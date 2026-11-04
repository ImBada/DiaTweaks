#import "Patches/SidebarAddressBar/Toolbar.h"
#import "Patches/HideToolbar/Layout.m"
#import "Patches/HideToolbar/HideToolbar.m"
#import "Patches/HideToolbar/Hover.m"
#import "Patches/HideToolbar/CopyToast.m"
#import "Patches/HideToolbar/RevealOnHover.m"
#import "Patches/HideToolbar/ShowWithSidebar.m"
#import "Patches/HideToolbar/ShowOnNewTab.m"

DPPatch DPSidebarAddressBar, DPSidebarComfortableSpacing, DPPlainSelectedTab, DPPeekToolbarOnCopy, DPCopyToast;
static BOOL available = YES, docked = YES, flipped = YES;
static NSMutableArray *launch;
BOOL DPSidebarAddressRowAvailable(NSWindow *window) { return available && DPSidebarAddressBar.on; }
BOOL DPBesideSidebar(NSView *view) { return docked; }
void DPRepaintTabs(NSWindow *window) {}
void DPSidebarApplyLayout(void) {}
void DPSidebarLayoutHeader(NSView *header) {}
void DPOnLaunch(void (^block)(void)) { [launch addObject:[block copy]]; }
@interface ToolbarFixtureView : NSView @end
@implementation ToolbarFixtureView
- (BOOL)isFlipped { return flipped; }
@end
static Class FixtureClass(const char *name) {
    Class cls = objc_allocateClassPair(ToolbarFixtureView.class, name, 0);
    objc_registerClassPair(cls); return cls;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    FixtureClass(DPDiaToolbar); FixtureClass(DPDiaContentPane);
    FixtureClass(DPDiaContentContainer); FixtureClass(DPDiaBookmarksBar);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    NSView *container = [[objc_getClass(DPDiaContentContainer) alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    window.contentView = container;
    NSView *pane = [[objc_getClass(DPDiaContentPane) alloc] initWithFrame:container.bounds];
    [container addSubview:pane];
    NSView *bar = [[objc_getClass(DPDiaToolbar) alloc] initWithFrame:NSMakeRect(0,0,800,40)];
    NSView *bookmarks = [[objc_getClass(DPDiaBookmarksBar) alloc] initWithFrame:NSMakeRect(0,40,800,20)];
    NSView *page = [[ToolbarFixtureView alloc] initWithFrame:NSMakeRect(0,60,800,540)];
    [pane addSubview:bar]; [pane addSubview:bookmarks]; [pane addSubview:page];
    [window orderFront:nil];
    DPPatch *patches[] = {&DPSidebarAddressBar,&DPSidebarHideTopToolbar,&DPHideToolbar,
        &DPRevealToolbarOnHover,&DPShowToolbarWithSidebar,&DPShowToolbarOnNewTab};
    DPPatches = patches; DPPatchCount = 6;
    launch = [NSMutableArray new]; DPInstallHideToolbar(); DPSidebarInstallToolbar();
    for (void (^block)(void) in launch) block();
    for (NSUInteger orientation=0; orientation<2; orientation++) {
    flipped = orientation == 0;
    bar.frame = NSMakeRect(0,flipped ? 0 : 560,800,40);
    bookmarks.frame = NSMakeRect(0,flipped ? 40 : 540,800,20);
    page.frame = NSMakeRect(0,flipped ? 60 : 0,800,540);
    for (NSUInteger bits=0; bits<16; bits++) {
        DPSidebarAddressBar.on = YES; DPSidebarHideTopToolbar.on = YES;
        DPHideToolbar.on = bits & 1; DPHideToolbar.progress = DPHideToolbar.on;
        DPRevealToolbarOnHover.on = bits & 2; DPShowToolbarWithSidebar.on = bits & 4;
        DPShowToolbarOnNewTab.on = bits & 8;
        for (NSUInteger i=0; i<10; i++) {
            DPSidebarRefreshToolbar();
            NSCAssert(bar.alphaValue == 0 && DPBottom(pane,bar.frame) == 0, @"replacement hides and lifts toolbar");
            NSCAssert(bookmarks.alphaValue == 1 && DPTop(pane,bookmarks.frame) == 0, @"bookmarks remain visible without drift");
            NSCAssert(DPTop(pane,page.frame) == 20 && NSHeight(page.frame) == 580, @"page fills toolbar space only");
            NSCAssert(!DPSidebarVerifyToolbar(), @"replacement verifier must check actual geometry");
        }
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        [hover peek]; NSCAssert(!hover.peeking && !hover.tracking, @"no hover or duplicate copy reveal");
        [(id)hover reset]; NSCAssert(DPTop(pane,page.frame) == 20, @"focus loss preserves replacement layout");
        page.frame = NSOffsetRect(page.frame,0,5);
        NSCAssert(DPSidebarVerifyToolbar(), @"verification detects broken page geometry");
        page.frame = NSOffsetRect(page.frame,0,-5);
        DPSidebarAddressBar.on = NO; DPHideToolbar.on = NO; DPHideToolbar.progress = 0;
        DPShowToolbarWithSidebar.on = DPShowToolbarOnNewTab.on = NO;
        DPSidebarRefreshToolbar();
        NSCAssert(bar.alphaValue == 1 && NSEqualRects(page.frame,NSMakeRect(0,flipped ? 60 : 0,800,540)), @"off restores upstream geometry");
    }
    }
    DPSidebarAddressBar.on = YES;
    docked = NO; DPSidebarRefreshToolbar(); NSCAssert(bar.alphaValue == 1, @"floating sidebar keeps native toolbar");
    docked = YES; available = NO; DPSidebarRefreshToolbar(); NSCAssert(bar.alphaValue == 1, @"horizontal/missing sidebar keeps native toolbar");
    [window close];
    puts("PASS: 32 flipped/unflipped toolbar option combinations, repeated layout, bookmarks, focus reset, copy reveal, restoration and verifier negative control");
} }
