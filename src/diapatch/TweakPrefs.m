#import "TweakPrefs.h"

id DPPref(NSString *key) {
    const char *custom = getenv("DIATWEAKS_DOMAIN");
    NSString *domain = custom && *custom ? @(custom) : @"com.diapatches";
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
}

BOOL DPTweakOn(NSString *home, NSString *key) {
    if ([NSFileManager.defaultManager fileExistsAtPath:[home stringByAppendingPathComponent:@"paused"]]) return NO;
    if ([[NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:@"safe-mode.plist"]][@"level"] integerValue] > 0) return NO;
    id on = DPPref(key);
    return [on respondsToSelector:@selector(boolValue)] && [on boolValue];
}
