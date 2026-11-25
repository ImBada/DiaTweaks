#import "GroupTabs.h"
#import <objc/message.h>

static long long DPParseLongLong(NSString *text) {
    char buffer[32], *end;
    if ([text getCString:buffer maxLength:sizeof buffer encoding:NSASCIIStringEncoding] && !isspace(buffer[0])) {
        long long number = strtoll(buffer, &end, 10);
        if (end != buffer && (NSUInteger)(end - buffer) == text.length) return number;
    }
    NSScanner *scanner = [NSScanner scannerWithString:text];
    long long number = 0;
    return [scanner scanLongLong:&number] && scanner.atEnd ? number : 0;
}

long long DPLongID(id value) {
    if (!value || value == NSNull.null) return 0;
    if ([value isKindOfClass:NSNumber.class]) return ((NSNumber *)value).longLongValue;
    if ([value isKindOfClass:NSString.class]) return DPParseLongLong(value);
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

void DPLoadTabGroups(id delegate, id browser, void (^use)(NSArray *groups)) {
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([groups isKindOfClass:NSArray.class]) use(groups);
        });
    });
}

void DPRemoveFromGroups(id delegate, id browser, NSArray *ids, void (^done)(void)) {
    void (*remove)(id, SEL, id, NSArray *, void (^)(id)) = (void *)objc_msgSend;
    remove(delegate, @selector(browser:removeTabsFromGroupWithSessionIds:completion:), browser, ids, ^(id _) {
        if (done) dispatch_async(dispatch_get_main_queue(), done);
    });
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
