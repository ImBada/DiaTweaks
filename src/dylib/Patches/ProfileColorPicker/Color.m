#import "ProfileColorPicker.h"

static NSString *const DPProfileColorsKey = @"profileColors";
static NSUserDefaults *DPColorDefaults;

static NSUserDefaults *DPDefaults(void) {
    if (!DPColorDefaults) DPColorDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    return DPColorDefaults;
}

static int DPHexDigit(unichar c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

static NSColor *DPParseHex(NSString *hex, BOOL allowShort, NSString **canonical) {
    if (![hex isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
    NSUInteger len = trimmed.length;
    if (len != 6 && !(allowShort && len == 3)) return nil;
    int digits[6];
    for (NSUInteger i = 0; i < len; i++) {
        digits[i] = DPHexDigit([trimmed characterAtIndex:i]);
        if (digits[i] < 0) return nil;
    }
    int r, g, b;
    if (len == 3) {
        r = digits[0] * 17;
        g = digits[1] * 17;
        b = digits[2] * 17;
    } else {
        r = (digits[0] << 4) | digits[1];
        g = (digits[2] << 4) | digits[3];
        b = (digits[4] << 4) | digits[5];
    }
    if (canonical) *canonical = [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
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

NSArray *DPProfileGradientColors(NSColor *base, BOOL dark, double intensity) {
    NSColor *srgb = DPSRGB(base);
    if (!srgb) return nil;
    if (!isfinite(intensity)) intensity = 0.0;
    intensity = MIN(MAX(intensity, -1.0), 1.1);
    double mult = intensity >= 1.0 ? 2.2 : (intensity > 0.0 ? 1.0 + 0.6 * intensity : 1.0);
    CGFloat alpha = MIN(1.0, (dark ? 0.58 : 0.62) * mult);
    NSColor *white = [NSColor colorWithSRGBRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    NSColor *topBase = [srgb blendedColorWithFraction:(dark ? 0.12 : 0.16) ofColor:white] ?: srgb;
    NSColor *top = [topBase colorWithAlphaComponent:alpha];
    NSColor *bottom = [srgb colorWithAlphaComponent:alpha];
    return @[ (__bridge id)top.CGColor, (__bridge id)bottom.CGColor ];
}

NSString *DPNormalizedSpaceID(id value) {
    if (!value || value == NSNull.null) return nil;
    NSString *s = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s hasPrefix:@"Optional("] && [s hasSuffix:@")"]) {
        s = [[s substringWithRange:NSMakeRange(9, s.length - 10)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    NSRange rawRange = [s rangeOfString:@"rawValue:"];
    if (rawRange.location != NSNotFound) {
        NSString *tail = [[s substringFromIndex:NSMaxRange(rawRange)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([tail hasSuffix:@")"]) tail = [tail substringToIndex:tail.length - 1];
        s = [tail stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"' \t\n"]];
    } else {
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
    }
    if (!s.length || [s isEqualToString:@"nil"] || [s isEqualToString:@"none"]) return nil;
    return s;
}

NSString *DPSavedProfileHexForSpace(NSString *spaceID) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    if (!key) return nil;
    NSDictionary *dict = [DPDefaults() dictionaryForKey:DPProfileColorsKey];
    NSString *raw = [dict isKindOfClass:NSDictionary.class] ? dict[key] : nil;
    NSString *canonical = nil;
    return DPColorFromHex(raw, &canonical) ? canonical : nil;
}

NSString *DPProfileHexForSpace(NSString *spaceID) {
    return DPProfileColorPicker.on ? DPSavedProfileHexForSpace(spaceID) : nil;
}

void DPSetProfileHexForSpace(NSString *spaceID, NSString *hex) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    if (!key) return;
    NSString *canonical = nil;
    if (hex.length && !DPColorFromHex(hex, &canonical)) return;
    NSDictionary *existing = [DPDefaults() dictionaryForKey:DPProfileColorsKey];
    NSMutableDictionary *colors = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    colors[key] = canonical;
    if (colors.count) [DPDefaults() setObject:colors forKey:DPProfileColorsKey];
    else [DPDefaults() removeObjectForKey:DPProfileColorsKey];
}
