#import "ProfileColorPicker.h"

static NSString *const DPProfileColorsKey = @"profileColors";

static int DPHexDigit(unichar c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

static BOOL DPParseHexRGB(NSString *hex, BOOL allowShort, int *rOut, int *gOut, int *bOut, NSString **canonical) {
    if (![hex isKindOfClass:NSString.class]) return NO;
    NSUInteger len = hex.length;
    if (len == 7 && [hex characterAtIndex:0] == '#') {
        int digits[6];
        BOOL upper = YES;
        for (NSUInteger i = 0; i < 6; i++) {
            unichar c = [hex characterAtIndex:i + 1];
            digits[i] = DPHexDigit(c);
            if (digits[i] < 0) return NO;
            if (c >= 'a' && c <= 'f') upper = NO;
        }
        int r = (digits[0] << 4) | digits[1], g = (digits[2] << 4) | digits[3], b = (digits[4] << 4) | digits[5];
        if (rOut) *rOut = r;
        if (gOut) *gOut = g;
        if (bOut) *bOut = b;
        if (canonical) *canonical = upper ? hex : [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
        return YES;
    }
    NSString *trimmed = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
    len = trimmed.length;
    if (len != 6 && !(allowShort && len == 3)) return NO;
    int digits[6];
    for (NSUInteger i = 0; i < len; i++) {
        digits[i] = DPHexDigit([trimmed characterAtIndex:i]);
        if (digits[i] < 0) return NO;
    }
    int r = len == 3 ? digits[0] * 17 : ((digits[0] << 4) | digits[1]);
    int g = len == 3 ? digits[1] * 17 : ((digits[2] << 4) | digits[3]);
    int b = len == 3 ? digits[2] * 17 : ((digits[4] << 4) | digits[5]);
    if (rOut) *rOut = r;
    if (gOut) *gOut = g;
    if (bOut) *bOut = b;
    if (canonical) *canonical = [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
    return YES;
}

static NSColor *DPParseHex(NSString *hex, BOOL allowShort, NSString **canonical) {
    int r = 0, g = 0, b = 0;
    if (!DPParseHexRGB(hex, allowShort, &r, &g, &b, canonical)) return nil;
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

NSColor *DPColorFromHex(NSString *hex, NSString **canonical) {
    return DPParseHex(hex, YES, canonical);
}

NSColor *DPColorFromSixDigitHex(NSString *hex, NSString **canonical) {
    return DPParseHex(hex, NO, canonical);
}

static NSColor *DPSRGB(NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!srgb && color.CGColor) srgb = [[NSColor colorWithCGColor:color.CGColor] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return srgb;
}

NSString *DPHexFromColor(NSColor *color) {
    NSColor *srgb = DPSRGB(color);
    if (!srgb) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [srgb getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", lround(DPUnit(r) * 255.0), lround(DPUnit(g) * 255.0), lround(DPUnit(b) * 255.0)];
}

typedef struct {
    uint64_t rBits, gBits, bBits, intensityBits;
    BOOL dark;
    __strong NSArray *colors;
} DPGradientCacheEntry;

static NSArray *DPGradientColorsForRGB(CGFloat r, CGFloat g, CGFloat b, BOOL dark, double intensity) {
    if (!isfinite(intensity)) intensity = 0.0;
    intensity = MIN(MAX(intensity, -1.0), 1.1);
    if (intensity == 0.0) intensity = 0.0;
    uint64_t rBits = 0, gBits = 0, bBits = 0, iBits = 0;
    memcpy(&rBits, &r, sizeof rBits);
    memcpy(&gBits, &g, sizeof gBits);
    memcpy(&bBits, &b, sizeof bBits);
    memcpy(&iBits, &intensity, sizeof iBits);

    enum { DPCacheSize = 64 };
    static DPGradientCacheEntry cache[DPCacheSize];
    static size_t cursor;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    for (size_t i = 0; i < DPCacheSize; i++) {
        DPGradientCacheEntry *entry = &cache[i];
        if (entry->colors && entry->dark == dark && entry->rBits == rBits && entry->gBits == gBits
            && entry->bBits == bBits && entry->intensityBits == iBits) {
            NSArray *hit = entry->colors;
            os_unfair_lock_unlock(&lock);
            return hit;
        }
    }
    os_unfair_lock_unlock(&lock);

    NSColor *srgb = [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
    double mult = intensity >= 1.0 ? 2.2 : (intensity > 0.0 ? 1.0 + 0.6 * intensity : 1.0);
    CGFloat alpha = MIN(1.0, (dark ? 0.58 : 0.62) * mult);
    static NSColor *white;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ white = [NSColor colorWithSRGBRed:1.0 green:1.0 blue:1.0 alpha:1.0]; });
    NSColor *topBase = [srgb blendedColorWithFraction:(dark ? 0.12 : 0.16) ofColor:white] ?: srgb;
    NSColor *top = [topBase colorWithAlphaComponent:alpha];
    NSColor *bottom = [srgb colorWithAlphaComponent:alpha];
    NSArray *built = @[ (__bridge id)top.CGColor, (__bridge id)bottom.CGColor ];

    os_unfair_lock_lock(&lock);
    cache[cursor] = (DPGradientCacheEntry){rBits, gBits, bBits, iBits, dark, built};
    cursor = (cursor + 1) % DPCacheSize;
    os_unfair_lock_unlock(&lock);
    return built;
}

NSArray *DPProfileGradientColors(NSColor *base, BOOL dark, double intensity) {
    NSColor *srgb = DPSRGB(base);
    if (!srgb) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [srgb getRed:&r green:&g blue:&b alpha:&a];
    return DPGradientColorsForRGB(r, g, b, dark, intensity);
}

NSArray *DPProfileGradientColorsForHex(NSString *hex, BOOL dark, double intensity) {
    int r = 0, g = 0, b = 0;
    if (!DPParseHexRGB(hex, YES, &r, &g, &b, NULL)) return nil;
    return DPGradientColorsForRGB(r / 255.0, g / 255.0, b / 255.0, dark, intensity);
}

static BOOL DPIsCleanSpaceString(NSString *s) {
    NSUInteger len = s.length;
    if (!len || (len == 3 && [s isEqualToString:@"nil"]) || (len == 4 && [s isEqualToString:@"none"])) return NO;
    if (len >= 9 && [s characterAtIndex:0] == 'O' && [s hasPrefix:@"Optional("]) return NO;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [s characterAtIndex:i];
        if (c <= ' ' || c == '"' || c == '\'' || c == ':') return NO;
    }
    return YES;
}

NSString *DPNormalizedSpaceID(id value) {
    if (!value || value == NSNull.null) return nil;
    if ([value isKindOfClass:NSString.class] && DPIsCleanSpaceString(value)) return value;
    static NSCharacterSet *ws, *quotesAndWS, *quotes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        quotesAndWS = [NSCharacterSet characterSetWithCharactersInString:@"\"' \t\n"];
        quotes = [NSCharacterSet characterSetWithCharactersInString:@"\"'"];
    });
    NSString *s = [[value description] stringByTrimmingCharactersInSet:ws];
    while ([s hasPrefix:@"Optional("] && [s hasSuffix:@")"]) {
        s = [[s substringWithRange:NSMakeRange(9, s.length - 10)] stringByTrimmingCharactersInSet:ws];
    }
    NSRange rawRange = [s rangeOfString:@"rawValue:"];
    if (rawRange.location != NSNotFound) {
        NSString *tail = [[s substringFromIndex:NSMaxRange(rawRange)] stringByTrimmingCharactersInSet:ws];
        if ([tail hasSuffix:@")"]) tail = [tail substringToIndex:tail.length - 1];
        s = [tail stringByTrimmingCharactersInSet:quotesAndWS];
    } else {
        s = [s stringByTrimmingCharactersInSet:quotes];
    }
    if (!s.length || [s isEqualToString:@"nil"] || [s isEqualToString:@"none"]) return nil;
    return s;
}

NSString *DPSavedProfileHexForSpace(NSString *spaceID) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    if (!key) return nil;
    NSDictionary *dict = [DPSettingsDefaults() dictionaryForKey:DPProfileColorsKey];
    NSString *raw = [dict isKindOfClass:NSDictionary.class] ? dict[key] : nil;
    NSString *canonical = nil;
    return DPParseHexRGB(raw, YES, NULL, NULL, NULL, &canonical) ? canonical : nil;
}

NSString *DPProfileHexForSpace(NSString *spaceID) {
    return DPProfileColorPicker.on ? DPSavedProfileHexForSpace(spaceID) : nil;
}

void DPSetProfileHexForSpace(NSString *spaceID, NSString *hex) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    if (!key) return;
    NSString *canonical = nil;
    if (hex.length && !DPParseHexRGB(hex, YES, NULL, NULL, NULL, &canonical)) return;
    NSDictionary *existing = [DPSettingsDefaults() dictionaryForKey:DPProfileColorsKey];
    NSMutableDictionary *colors = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    colors[key] = canonical;
    if (colors.count) [DPSettingsDefaults() setObject:colors forKey:DPProfileColorsKey];
    else [DPSettingsDefaults() removeObjectForKey:DPProfileColorsKey];
}
