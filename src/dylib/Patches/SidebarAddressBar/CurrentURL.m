#import "SidebarAddressBar.h"
#import "WindowTabs.h"

NSString *DPSidebarURL(NSWindow *window) {
    NSString *saved = DPWindowTabURL(window);
    NSURLComponents *base = [NSURLComponents componentsWithString:saved ?: @""];
    if (!base.host.length || base.user.length || base.password.length ||
        ![@[@"http", @"https"] containsObject:base.scheme.lowercaseString]) return saved;
    // Pinned tabs' scripting URL can remain at the saved pin after navigation.
    // Dia's own toolbar follows the live page, including its path/query/fragment.
    NSView *toolbar = DPWindowSourceToolbar(window);
    NSView *field = DPFindView(toolbar, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaAddressField); });
    if ([window.firstResponder isKindOfClass:NSView.class] && [(NSView *)window.firstResponder isDescendantOf:field]) return saved;
    NSTextView *text = (NSTextView *)DPFindView(field, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextView.class]; });
    NSString *value = [text.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length || [value containsString:@"…"] ||
        [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return saved;
    if (![value containsString:@"://"]) value = [NSString stringWithFormat:@"%@://%@", base.scheme, value];
    NSURLComponents *current = [NSURLComponents componentsWithString:value];
    NSString *expectedHost = base.host.lowercaseString, *actualHost = current.host.lowercaseString;
    if ([expectedHost hasPrefix:@"www."]) expectedHost = [expectedHost substringFromIndex:4];
    if ([actualHost hasPrefix:@"www."]) actualHost = [actualHost substringFromIndex:4];
    if (!actualHost.length || ![expectedHost isEqual:actualHost] || current.user.length || current.password.length ||
        ![@[@"http", @"https"] containsObject:current.scheme.lowercaseString]) return saved;
    return current.URL.absoluteString ?: saved;
}
