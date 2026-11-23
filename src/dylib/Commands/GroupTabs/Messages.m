#import "GroupTabs.h"
#import <objc/message.h>

long long DPLongID(id value) {
    if (!value || value == NSNull.null) return 0;
    if ([value isKindOfClass:NSNumber.class]) return ((NSNumber *)value).longLongValue;
    if ([value isKindOfClass:NSString.class]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        long long number = 0;
        return [scanner scanLongLong:&number] && [scanner isAtEnd] ? number : 0;
    }
    if ([value respondsToSelector:@selector(identifier)]) {
        NSInteger (*msg)(id, SEL) = (void *)objc_msgSend;
        return msg(value, @selector(identifier));
    }
    return 0;
}

id DPMsg(id object, SEL sel) {
    id (*msg)(id, SEL) = (void *)objc_msgSend;
    return object ? msg(object, sel) : nil;
}

BOOL DPMsgBool(id object, SEL sel) {
    BOOL (*msg)(id, SEL) = (void *)objc_msgSend;
    return object ? msg(object, sel) : NO;
}

static NSArray *DPScriptArray(id owner, SEL sel) {
    NSArray *array = [owner respondsToSelector:sel] ? DPMsg(owner, sel) : nil;
    return [array isKindOfClass:NSArray.class] ? array : nil;
}

NSArray *DPAppleScriptWindows(void) { return DPScriptArray(NSApp.delegate, @selector(appleScriptWindows)); }

NSArray *DPAppleScriptTabs(id window) { return DPScriptArray(window, @selector(appleScriptTabs)); }

NSString *DPText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return ((NSURL *)value).absoluteString;
    if ([value isKindOfClass:NSNumber.class]) return ((NSNumber *)value).stringValue;
    return nil;
}
