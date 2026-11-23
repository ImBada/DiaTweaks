#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import "StdPatch/StdPatch.h"
#import "Settings/Settings.h"
#import "runloop.h"

NSString *DPTabLayout(void) { return @"vertical"; }
void DPHook(const char *className, SEL sel, IMP replacement) {}
IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame) { return NULL; }
void DPPopOriginalIMP(DPHookFrame *frame) {}
DPPatch *DPRequired(DPPatch *patch) { return nil; }
BOOL DPIsLocalPatch(DPPatch *patch) { return NO; }
DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
NSView *DPFindView(NSView *root, BOOL (^match)(NSView *)) { return nil; }

#define DP_PREVIEWS "http://127.0.0.1:1/nonexistent/"
#import "Settings/Controls.m"
#import "Settings/Preview.m"

static int failures;
static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    fprintf(stderr, "FAIL %s\n", what.UTF8String);
}

static void writeSolidPNG(NSURL *url, size_t width, size_t height) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 0.2, 0.4, 0.8, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)@"public.png", 1, NULL);
    CGImageDestinationAddImage(dest, cg, NULL);
    expect(CGImageDestinationFinalize(dest), @"write synthetic preview image");
    CFRelease(dest);
    CGImageRelease(cg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"preview-test-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:nil];

        NSURL *corruptWebp = [NSURL fileURLWithPath:[temp stringByAppendingPathComponent:@"vertical-bad-onoff.webp"]];
        [NSData.data writeToURL:corruptWebp atomically:YES];
        DPPreviewView *badView = [[DPPreviewView alloc] initWithKey:@"bad-nonexistent-key"];
        [badView show:corruptWebp];
        expect(badView.hidden, @"corrupt 0-byte -onoff.webp falls back to hidden cleanly");

        NSURL *thinWebp = [NSURL fileURLWithPath:[temp stringByAppendingPathComponent:@"vertical-thin-onoff.webp"]];
        writeSolidPNG(thinWebp, 4, 1);
        [badView show:thinWebp];
        expect(badView.hidden, @"1px-tall -onoff.webp hides cleanly");

        NSURL *goodWebp = [NSURL fileURLWithPath:[temp stringByAppendingPathComponent:@"vertical-good-onoff.webp"]];
        writeSolidPNG(goodWebp, 4, 4);
        __weak DPPreviewView *weakPreview = nil;
        @autoreleasepool {
            NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
            win.releasedWhenClosed = NO;
            DPPreviewView *preview = [[DPPreviewView alloc] initWithKey:@"good-nonexistent-key"];
            weakPreview = preview;
            [win.contentView addSubview:preview];
            [preview show:goodWebp];
            expect(!preview.hidden, @"valid 4x4 -onoff.webp displays cleanly");
            [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:win];
            [win close];
        }
        DPDrainMainQueue(0.05);
        expect(weakPreview == nil, @"DPPreviewView deallocates without NSTimer/CADisplayLink retain cycle");

        __block BOOL emptyFetched = NO;
        __block NSURL *emptyFile = (NSURL *)NSNull.null;
        DPFetchPreview(@[], ^(NSURL *file, BOOL changed) {
            emptyFile = file;
            emptyFetched = YES;
        });
        expect(emptyFetched && emptyFile == nil, @"DPFetchPreview handles empty candidate list cleanly");

        __block BOOL offlineFetched = NO;
        __block NSURL *offlineFile = (NSURL *)NSNull.null;
        DPFetchPreview(@[ @"offline-preview-check.webp" ], ^(NSURL *file, BOOL changed) {
            offlineFile = file;
            offlineFetched = YES;
        });
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!offlineFetched && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        expect(offlineFetched && offlineFile == nil, @"DPFetchPreview handles offline/unreachable server cleanly");

        [NSFileManager.defaultManager removeItemAtPath:temp error:nil];
    }
    if (!failures) puts("all settings preview checks passed");
    return failures ? 1 : 0;
}
