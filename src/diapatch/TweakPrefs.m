#import "TweakPrefs.h"

static NSString *activeDomain(void) {
    const char *custom = getenv("DIATWEAKS_DOMAIN");
    return custom && *custom ? @(custom) : @"com.diapatches";
}

static BOOL truthy(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

id DPPref(NSString *key) {
    NSString *domain = activeDomain();
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
}

BOOL DPTweakOn(NSString *home, NSString *key) {
    if ([NSFileManager.defaultManager fileExistsAtPath:[home stringByAppendingPathComponent:@"paused"]]) return NO;
    if ([[NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:@"safe-mode.plist"]][@"level"] integerValue] > 0) return NO;
    return truthy(DPPref(key));
}

void DPMigratePrefs(void) {
    if (truthy(DPPref(@"peekTurnedOffForNative"))) return;
    NSString *domain = activeDomain();
    BOOL peeking = truthy(DPPref(@"peek"));
    CFPreferencesSetAppValue(CFSTR("peekTurnedOffForNative"), kCFBooleanTrue, (__bridge CFStringRef)domain);
    if (peeking) CFPreferencesSetAppValue(CFSTR("peek"), kCFBooleanFalse, (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}
