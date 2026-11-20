#import "WindowTabs.h"
#import <objc/message.h>

// Check selectors before reading Dia's private scripting facade. A changed facade leaves an empty row.
static id DPRead(id object, NSString *key) {
    SEL selector = NSSelectorFromString(key);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

// Dia constructs scripting facades for every window here. Layout and refresh
// can ask for the same list many times in one event; share that list until the
// next main-queue turn, while still reading each facade's active tab afresh.
static NSArray *DPWindowScriptFacades(void) {
    static NSArray *windows;
    if (!windows) {
        windows = DPRead(NSApp.delegate, @"appleScriptWindows");
        dispatch_async(dispatch_get_main_queue(), ^{ windows = nil; });
    }
    return windows;
}

static id DPWindowActiveTab(NSWindow *window) {
    for (id scripted in DPWindowScriptFacades())
        if ([DPRead(scripted, @"windowId") isEqual:window.identifier]) return DPRead(scripted, @"activeTab");
    return nil;
}

NSString *DPWindowTabURL(NSWindow *window) {
    id url = DPRead(DPWindowActiveTab(window), @"URL");
    if ([url isKindOfClass:NSURL.class]) return [url absoluteString];
    return [url isKindOfClass:NSString.class] ? url : nil;
}

NSString *DPWindowTabIdentifier(NSWindow *window) {
    id identifier = DPRead(DPWindowActiveTab(window), @"tabId");
    return [identifier isKindOfClass:NSString.class] ? identifier : nil;
}

NSString *DPWindowTabTitle(NSWindow *window) {
    id title = DPRead(DPWindowActiveTab(window), @"title");
    return [title isKindOfClass:NSString.class] ? title : nil;
}

NSView *DPWindowSourceToolbar(NSWindow *window) {
    __block NSView *fallback;
    NSString *url = DPWindowTabURL(window);
    NSString *host = url.length ? [NSURLComponents componentsWithString:url].host : nil;
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    NSView *matched = DPFindView(window.contentView, ^BOOL(NSView *view) {
        if (!DPIsKind(view, DPDiaToolbar) || view.hiddenOrHasHiddenAncestor) return NO;
        if (!fallback) fallback = view;
        NSView *field = DPFindView(view, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaAddressField); });
        NSTextView *text = (NSTextView *)DPFindView(field, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextView.class]; });
        return host.length && text.string.length && [text.string rangeOfString:host options:NSCaseInsensitiveSearch].location != NSNotFound;
    });
    return matched ?: fallback;
}
