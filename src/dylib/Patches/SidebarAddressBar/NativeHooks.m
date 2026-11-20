#import "NativeSlot.h"

static BOOL DPOwnedNative(DPAddressNativeSlot *slot) { return slot.owner && !slot.moving; }

static void DPAddressNative_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(self);
    BOOL moving = slot.moving;
    if (DPOwnedNative(slot)) {
        slot.originalFrame = frame;
        if (slot.pinned) {
            slot.naturalWidth = MAX(0, NSWidth(frame));
            if (!slot.fixedPinnedWidth) slot.forcedFrame = NSMakeRect(0, 0, slot.naturalWidth, 42);
        }
        frame = slot.forcedFrame;
        slot.moving = YES;
    }
    DPCallOriginal(DPAddressNative_setFrame, self, frame);
    if (slot) slot.moving = moving;
}

static void DPAddressNative_setOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(self);
    if (DPOwnedNative(slot)) { slot.originalFrame = (NSRect){origin, slot.originalFrame.size}; origin = slot.forcedFrame.origin; }
    DPCallOriginal(DPAddressNative_setOrigin, self, origin);
}

static void DPAddressNative_setSize(NSView *self, SEL _cmd, NSSize size) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(self);
    if (DPOwnedNative(slot)) {
        slot.originalFrame = (NSRect){slot.originalFrame.origin, size};
        if (slot.pinned) {
            slot.naturalWidth = MAX(0, size.width);
            NSRect forced = slot.forcedFrame;
            if (!slot.fixedPinnedWidth) forced.size.width = slot.naturalWidth;
            slot.forcedFrame = forced;
        }
        size = slot.forcedFrame.size;
    }
    DPCallOriginal(DPAddressNative_setSize, self, size);
}

static void DPAddressNative_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(self);
    if (DPOwnedNative(slot)) { slot.originalHidden = hidden; hidden = slot.forcedHidden; }
    DPCallOriginal(DPAddressNative_setHidden, self, hidden);
}

static void DPAddressNative_setAlpha(NSView *self, SEL _cmd, CGFloat alpha) {
    DPAddressNativeSlot *slot = DPAddressNativeSlotFor(self);
    if (DPOwnedNative(slot)) { slot.originalAlpha = alpha; alpha = 1; }
    DPCallOriginal(DPAddressNative_setAlpha, self, alpha);
}

void DPInstallAddressNativeHooks(NSView *view) {
    DPHookClass(view.class, @selector(setFrame:), (IMP)DPAddressNative_setFrame);
    DPHookClass(view.class, @selector(setFrameOrigin:), (IMP)DPAddressNative_setOrigin);
    DPHookClass(view.class, @selector(setFrameSize:), (IMP)DPAddressNative_setSize);
    DPHookClass(view.class, @selector(setHidden:), (IMP)DPAddressNative_setHidden);
    DPHookClass(view.class, @selector(setAlphaValue:), (IMP)DPAddressNative_setAlpha);
}
