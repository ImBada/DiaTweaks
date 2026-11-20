#import "Editor.h"

static char DPInlineOwnerKey;
@interface DPInlineOwner : NSObject
@property (weak) DPSidebarAddressRow *row;
@property BOOL previousMouseMoved;
@property NSEventType capturedDown;
@end
@implementation DPInlineOwner @end

static void DPInlineApp_sendEvent(NSApplication *app, SEL _cmd, NSEvent *event) {
    NSWindow *window = event.window ?: [app windowWithWindowNumber:event.windowNumber];
    DPInlineOwner *owner = DPGet(window, &DPInlineOwnerKey);
    DPSidebarAddressRow *row = owner.row;
    if (row.inlineEditor && !row.window.attachedSheet) {
        NSPoint point = [row convertPoint:event.locationInWindow fromView:nil];
        BOOL inside = NSPointInRect(point, row.bounds);
        BOOL list = row.suggestions && NSPointInRect(point, row.suggestions.frame);
        if (event.type == NSEventTypeMouseMoved && list) {
            [NSCursor.arrowCursor set];
            [row.suggestions mouseMoved:event];
            return;
        }
        if ((event.type == NSEventTypeLeftMouseUp && owner.capturedDown == NSEventTypeLeftMouseDown) ||
            (event.type == NSEventTypeRightMouseUp && owner.capturedDown == NSEventTypeRightMouseDown)) {
            owner.capturedDown = 0;
            return;
        }
        if (inside && (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown)) {
            owner.capturedDown = event.type;
            if (list) {
                if (event.type == NSEventTypeLeftMouseDown) [row.suggestions mouseDown:event];
                return;
            }
            NSTextView *editor = row.addressFieldEditor;
            if (event.type == NSEventTypeRightMouseDown) {
                [editor rightMouseDown:event];
                owner.capturedDown = 0;
            }
            else if (editor.selectedRange.length == editor.string.length && editor.selectedRange.length) {
                editor.selectedRange = NSMakeRange(editor.string.length, 0);
                [editor scrollRangeToVisible:editor.selectedRange];
            } else {
                [editor mouseDown:event];
                owner.capturedDown = 0;
            }
            return;
        }
    }
    DPCallOriginal(DPInlineApp_sendEvent, app, event);
}

static BOOL DPInlineWindow_makeFirstResponder(NSWindow *window, SEL _cmd, NSResponder *responder) {
    DPSidebarAddressRow *row = [(DPInlineOwner *)DPGet(window, &DPInlineOwnerKey) row];
    if (row.inlineEditor && !responder && window.isKeyWindow) return YES;
    if (row.inlineEditor && [responder isKindOfClass:NSView.class]) {
        for (NSView *view = (NSView *)responder; view; view = view.superview) {
            if (DPIsKind(view, DPDiaCommandBarText)) {
                NSResponder *inlineResponder = row.inlineEditor.currentEditor ?: row.inlineEditor;
                if (window.firstResponder == inlineResponder) return YES;
                return DPCallOriginal(DPInlineWindow_makeFirstResponder, window, inlineResponder);
            }
        }
    }
    return DPCallOriginal(DPInlineWindow_makeFirstResponder, window, responder);
}

void DPSidebarInstallInlineFocus(void) {
    DPHookClass(NSWindow.class, @selector(makeFirstResponder:), (IMP)DPInlineWindow_makeFirstResponder);
}

void DPSidebarSetInlineOwner(DPSidebarAddressRow *row, BOOL active) {
    NSWindow *window = active ? row.window : (row.inlineHostWindow ?: row.window);
    DPInlineOwner *previous = DPGet(window, &DPInlineOwnerKey);
    if (previous) window.acceptsMouseMovedEvents = previous.previousMouseMoved;
    DPInlineOwner *owner = active ? [DPInlineOwner new] : nil;
    owner.row = row;
    if (active) {
        owner.previousMouseMoved = window.acceptsMouseMovedEvents;
        window.acceptsMouseMovedEvents = YES;
        DPHookClass(NSApp.class, @selector(sendEvent:), (IMP)DPInlineApp_sendEvent);
    }
    DPSet(window, &DPInlineOwnerKey, owner);
    row.inlineHostWindow = active ? window : nil;
}
