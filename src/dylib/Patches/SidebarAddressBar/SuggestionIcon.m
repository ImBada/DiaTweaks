#import "Editor.h"

NSImage *DPSidebarSuggestionIcon(NSImage *image) {
    if (!image || image.isTemplate) return image;
    static NSMapTable<NSImage *, NSImage *> *templates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ templates = [NSMapTable weakToStrongObjectsMapTable]; });
    NSImage *cached = [templates objectForKey:image];
    if (cached) return cached;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    if (!bitmap || bitmap.pixelsWide > 128 || bitmap.pixelsHigh > 128) return image;
    BOOL whiteOnly = YES, blackOnly = YES, visible = NO;
    for (NSInteger y = 0; y < bitmap.pixelsHigh && (whiteOnly || blackOnly); y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
            if (!color || color.alphaComponent < 0.1) continue;
            visible = YES;
            whiteOnly &= color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9;
            blackOnly &= color.redComponent < 0.1 && color.greenComponent < 0.1 && color.blueComponent < 0.1;
            if (!whiteOnly && !blackOnly) break;
        }
    }
    // Some native favicons are monochrome artwork without the template flag.
    // Tint those for contrast; preserve the actual colors of other favicons.
    if (!visible || (!whiteOnly && !blackOnly)) return image;
    NSImage *result = image.copy;
    result.template = YES;
    [templates setObject:result forKey:image];
    return result;
}
