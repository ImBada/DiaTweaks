#import "Patches/SidebarAddressBar/NativeControls.h"
DPPatch DPSidebarAddressBar;
DPAddressNativeControls *DPAddressControlsFor(NSView *row, BOOL create) { return nil; }
@interface NativeControlFixture : NSView
@property NSUInteger visibilityWrites, alphaWrites;
@end
@implementation NativeControlFixture
- (void)setHidden:(BOOL)hidden { self.visibilityWrites++; [super setHidden:hidden]; }
- (void)setAlphaValue:(CGFloat)alpha { self.alphaWrites++; [super setAlphaValue:alpha]; }
@end

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DPSidebarAddressBar.on = YES;
    NSStackView *home = [[NSStackView alloc] initWithFrame:NSMakeRect(0,0,800,40)];
    NSView *before = [NSView new], *after = [NSView new];
    NativeControlFixture *native = [[NativeControlFixture alloc] initWithFrame:NSMakeRect(500,4,22,22)];
    [home addView:before inGravity:NSStackViewGravityLeading];
    [home addView:native inGravity:NSStackViewGravityLeading];
    [home addView:after inGravity:NSStackViewGravityLeading];
    native.hidden = YES; native.alphaValue = 0.5;
    NSRect original = native.frame;
    NSView *owner = [[NSView alloc] initWithFrame:NSMakeRect(0,0,220,36)];
    native.wantsLayer = YES;
    native.layer.cornerRadius = 5;
    DPAddressNativeSlot *slot = DPAttachAddressNative(native,owner,owner,NSMakeRect(190,7,22,22),NO);
    NSCAssert(slot.view == native && native.superview == owner, @"move the exact native control, not a clone");
    NSCAssert(!native.hidden && native.alphaValue == 1, @"native hover-only control must be visible in sidebar");
    NSUInteger visibility = native.visibilityWrites, alpha = native.alphaWrites;
    for (NSUInteger i=0; i<100; i++) DPLayoutAddressNative(slot, slot.forcedFrame);
    NSCAssert(native.visibilityWrites == visibility && native.alphaWrites == alpha, @"steady layout must not re-trigger native visibility or opacity animations");
    native.frame = NSMakeRect(600,4,22,22);
    NSCAssert(NSEqualRects(native.frame,slot.forcedFrame), @"native toolbar layout cannot pull the sidebar control back");
    native.frameOrigin = NSMakePoint(700,4);
    NSCAssert(NSEqualPoints(native.frame.origin,slot.forcedFrame.origin), @"native origin changes must remain in the sidebar slot");
    CGFloat originalRadius = native.layer.cornerRadius;
    BOOL originalClipping = native.layer.masksToBounds;
    DPAddressStyleSiteHover(slot);
    native.layer.cornerRadius = 5;
    native.layer.masksToBounds = NO;
    NSCAssert(native.layer.cornerRadius == 9 && native.layer.masksToBounds, @"native redraw must preserve rounded hover");
    CALayer *oldLayer = native.layer;
    CALayer *replacement = [CALayer layer];
    replacement.cornerRadius = 3;
    native.layer = replacement;
    CGFloat replacementRadius = replacement.cornerRadius;
    BOOL replacementClipping = replacement.masksToBounds;
    DPAddressStyleSiteHover(slot);
    NSCAssert(oldLayer.cornerRadius == originalRadius && oldLayer.masksToBounds == originalClipping,
              @"the previous space's layer should get its native style back");
    NSCAssert(replacement.cornerRadius == 9 && replacement.masksToBounds,
              @"a rebuilt site button layer should receive the rounded hover style");
    DPRestoreAddressNative(slot);
    NSCAssert(replacement.cornerRadius == replacementRadius && replacement.masksToBounds == replacementClipping,
              @"the rebuilt layer should restore its own native style");
    native.layer = oldLayer;
    NSArray *arranged = [home viewsInGravity:NSStackViewGravityLeading];
    NSCAssert(arranged.count == 3 && arranged[1] == native, @"restore original stack order and gravity");
    NSCAssert(native.hidden && native.alphaValue == 0.5, @"restore native visibility and alpha");
    NSCAssert(NSMinX(native.frame) == 700, @"restore the most recent native requested position");
    NSCAssert(!DPAddressNativeSlotFor(native), @"release ownership marker on restoration");
    slot = DPAttachAddressNative(native,owner,owner,NSMakeRect(190,7,22,22),NO);
    [home removeView:native];
    NSCAssert(!slot.view && !native.superview, @"Dia must be able to remove a borrowed native control");
    NSCAssert([[home viewsInGravity:NSStackViewGravityLeading] isEqual:(@[before,after])], @"native removal must preserve neighboring controls");
    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0,0,1000,42)];
    NativeControlFixture *extensions = [[NativeControlFixture alloc] initWithFrame:NSMakeRect(800,0,120,42)];
    [toolbar addSubview:extensions];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,100,42)];
    slot = DPAttachAddressNative(extensions,owner,scroll.contentView,NSMakeRect(0,0,120,42),YES);
    NSCAssert(scroll.documentView == extensions, @"native extension hierarchy must remain intact in scroll document");
    extensions.frameSize = NSMakeSize(180,42);
    NSCAssert(slot.naturalWidth == 180 && NSWidth(extensions.frame) == 180, @"native pin changes must update document width");
    DPLayoutAddressNative(slot,NSMakeRect(0,0,180,42));
    NSCAssert(slot.naturalWidth == 180, @"sidebar layout must not overwrite native extension width");
    DPRestoreAddressNative(slot);
    NSCAssert(extensions.superview == toolbar && !scroll.documentView, @"restore extensions and clear the scroll document reference");
    NativeControlFixture *unowned = [[NativeControlFixture alloc] initWithFrame:original];
    unowned.frame = NSMakeRect(1,2,3,4);
    NSCAssert(NSEqualRects(unowned.frame,NSMakeRect(1,2,3,4)), @"unowned native controls must remain unaffected");
    puts("PASS: native control identity, stack restoration, visibility, layout isolation, extension sizing, and scroll ownership");
} }
