#import "StdPatch/StdPatch.h"

// Native controls retain their original parent, layout and visibility for restoration.
@interface DPAddressNativeSlot : NSObject
@property(weak) NSView *view, *home, *owner;
@property NSRect originalFrame, forcedFrame;
@property NSUInteger index;
@property NSStackViewGravity gravity;
@property BOOL moving, pinned, fixedPinnedWidth, originalHidden, forcedHidden, originalTranslates;
@property CGFloat originalAlpha, naturalWidth;
@property NSAutoresizingMaskOptions originalMask;
@property NSArray<NSLayoutConstraint *> *constraints;
@property(weak) NSImageView *icon;
@property NSImage *originalImage;
@property NSImage *displayImage;
@property NSColor *originalTint;
@property(weak) CALayer *styledHoverLayer;
@property BOOL originalMasksToBounds;
@property CGFloat originalCornerRadius;
@end

DPAddressNativeSlot *DPAttachAddressNative(NSView *view, NSView *owner, NSView *destination, NSRect frame, BOOL pinned);
void DPAddressStyleSiteHover(DPAddressNativeSlot *slot);
void DPRestoreAddressNative(DPAddressNativeSlot *slot);
void DPLayoutAddressNative(DPAddressNativeSlot *slot, NSRect frame);
void DPInstallAddressNativeHooks(NSView *view);
DPAddressNativeSlot *DPAddressNativeSlotFor(NSView *view);
