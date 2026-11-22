#import "Patches/Peek/Peek.h"
#import <objc/message.h>

#define DPDiaWindowController "_TtC6Window24PlatformWindowController"

static BOOL DPPeekIsZoom(SEL action) {
    return action == @selector(zoomIn:) || action == @selector(zoomInAlternate:) || action == @selector(zoomOut:) || action == @selector(resetZoom:);
}

static BOOL DPPeekZoomFrom(id page, SEL action, float *now, float *next) {
    BOOL reset = action == @selector(resetZoom:);
    if (![page respondsToSelector:@selector(zoomFactor)] || ![page respondsToSelector:reset ? @selector(resetZoomAndScaleFactors) : @selector(setZoomFactor:)]) return NO;
    *now = ((float (*)(id, SEL))objc_msgSend)(page, @selector(zoomFactor));
    *next = reset ? 1 : DPZoomStep(*now, action == @selector(zoomOut:) ? -1 : 1);
    return YES;
}

static BOOL DPPeekZoom(DPPeekCard *peek, SEL action) {
    id page = peek.page;
    float now, next;
    if (!DPPeekZoomFrom(page, action, &now, &next)) return NO;
    if (action == @selector(resetZoom:)) ((void (*)(id, SEL))objc_msgSend)(page, @selector(resetZoomAndScaleFactors));
    else ((void (*)(id, SEL, float))objc_msgSend)(page, @selector(setZoomFactor:), next);
    return YES;
}

static SEL DPPeekZoomShortcutIn(NSMenu *menu, NSEvent *event) {
    for (NSMenuItem *item in menu.itemArray) {
        if (DPPeekIsZoom(item.action) && DPPeekIsShortcut(event, item)) return item.action;
        SEL action = DPPeekZoomShortcutIn(item.submenu, event);
        if (action) return action;
    }
    return NULL;
}

BOOL DPPeekZoomShortcut(DPPeekCard *peek, NSEvent *event) {
    SEL action = DPPeekZoomShortcutIn(NSApp.mainMenu, event);
    return action && DPPeekZoom(peek, action);
}

static void DPWindow_zoom(NSWindowController *self, SEL _cmd, id sender) {
    if (DPPeek.on && DPPeekHasCards()) DPPeekSyncTabs(self.window);
    DPPeekCard *peek = DPPeek.on ? DPPeekCardIn(self.window) : nil;
    if (!peek || !DPPeekZoom(peek, _cmd)) DPCallOriginal(DPWindow_zoom, self, sender);
}

static BOOL DPWindow_validate(NSWindowController *self, SEL _cmd, NSMenuItem *item) {
    if (DPPeek.on && DPPeekIsZoom(item.action) && DPPeekHasCards()) DPPeekSyncTabs(self.window);
    DPPeekCard *peek = DPPeek.on && DPPeekIsZoom(item.action) ? DPPeekCardIn(self.window) : nil;
    float now, next;
    if (!peek || !DPPeekZoomFrom(peek.page, item.action, &now, &next)) return DPCallOriginal(DPWindow_validate, self, item);
    return fabsf(next - now) > 0.001;
}

void DPPeekInstallZoom(void) {
    SEL actions[] = {@selector(zoomIn:), @selector(zoomInAlternate:), @selector(zoomOut:), @selector(resetZoom:)};
    for (NSUInteger i = 0; i < 4; i++) DPHook(DPDiaWindowController, actions[i], (IMP)DPWindow_zoom);
    DPHook(DPDiaWindowController, @selector(validateMenuItem:), (IMP)DPWindow_validate);
}

NSString *DPPeekZoomProblem(void) {
    Class controller = objc_getClass(DPDiaWindowController);
    SEL actions[] = {@selector(zoomIn:), @selector(zoomInAlternate:), @selector(zoomOut:), @selector(resetZoom:)};
    for (NSUInteger i = 0; i < 4; i++)
        if (!DPIsHooked(controller, actions[i], (IMP)DPWindow_zoom)) return @"zoom doesn't reach Peek";
    return DPIsHooked(controller, @selector(validateMenuItem:), (IMP)DPWindow_validate) ? nil : @"zoom menu items don't reach Peek";
}
