#import <unistd.h>
#import "Test/Test.m"
#import "Patches/HideToolbar/HideToolbar.h"

BOOL DPBesideSidebar(NSView *container) { return NO; }
BOOL DPLittleDiaIsOver(NSWindow *window) { return NO; }
void DPRepaintTabs(NSWindow *window) {}
void DPOnLaunch(void (^block)(void)) {}
void DPApplyHides(DPPatch *patch) {}
NSString *DPVerifyHides(DPPatch *patch) { return nil; }
void DPInstallHides(void) {}
NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
BOOL DPPauseSaved(void) { return NO; }
BOOL DPLocalSafeModeOff(void) { return NO; }

static NSView *gPane;
static BOOL gStalledAtTheEnd, gStalledFading;

@interface Page : NSView
@end
@implementation Page
- (void)setFrame:(NSRect)frame {
    CGFloat hidden = DPHideToolbar.progress, kept = [DPToolbarHover forPane:gPane].inPlaceProgress;
    BOOL atTheEnd = !DPShowToolbarWithTopTabs.on && hidden > 0.995 && hidden < 1, fading = DPShowToolbarWithTopTabs.on && hidden > 0.2 && kept > 0.3 && kept < 0.9;
    if ((atTheEnd && !gStalledAtTheEnd) || (fading && !gStalledFading)) {
        gStalledAtTheEnd |= atTheEnd;
        gStalledFading |= fading;
        usleep(1000000);
    }
    [super setFrame:frame];
}
@end

@interface Window : NSWindow
@end
@implementation Window
- (BOOL)isVisible { return YES; }
@end

static NSArray<NSString *> *scenario(NSString *name, NSArray<NSString *> *keys) {
    NSMutableString *bits = [NSMutableString string];
    for (NSUInteger i = 0; i < DPPatchCount; i++) [bits appendString:[keys containsObject:DPPatches[i]->key] ? @"1" : @"0"];
    return @[name, bits];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        objc_registerClassPair(objc_allocateClassPair(NSView.class, DPDiaContentPane, 0));
        objc_registerClassPair(objc_allocateClassPair(NSView.class, DPDiaToolbar, 0));
        objc_registerClassPair(objc_allocateClassPair(NSView.class, DPDiaBookmarksBar, 0));
        DPLoadPatches();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->on = NO, DPPatches[i]->progress = 0;
        DPHideToolbar.install();

        Window *window = [[Window alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 800) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        gPane = [[NSClassFromString(@(DPDiaContentPane)) alloc] initWithFrame:window.contentView.bounds];
        [gPane addSubview:[[NSClassFromString(@(DPDiaToolbar)) alloc] initWithFrame:NSMakeRect(0, 750, 1000, 50)]];
        [gPane addSubview:[[Page alloc] initWithFrame:NSMakeRect(0, 0, 1000, 750)]];
        [window.contentView addSubview:gPane];
        DPApplyToolbar(gPane);

        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"hide-toolbar-settle-%d.json", getpid()]];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        NSMutableArray<NSArray<NSString *> *> *scenarios = [NSMutableArray arrayWithObjects:
            scenario(@"hidden, a frame stalls just before the end", @[@"hideToolbar", @"revealToolbarOnHover"]),
            scenario(@"off", @[]),
            scenario(@"kept in place, a frame stalls while it fades in", @[@"hideToolbar", @"showToolbarWithTopTabs"]), nil];
        DPRunScenario(scenarios, 0, [NSMutableArray new], path);
        NSDate *giveUp = [NSDate dateWithTimeIntervalSinceNow:60];
        while (![NSFileManager.defaultManager fileExistsAtPath:path] && giveUp.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        if (!data) return puts("FAIL: no report"), 1;

        int failures = !gStalledAtTheEnd || !gStalledFading;
        if (failures) puts("FAIL: the animation never reached the point to stall at");
        NSDictionary *report = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        for (NSDictionary *result in report[@"scenarios"])
            for (NSString *key in result[@"failures"]) printf("FAIL %s: %s: %s\n", [result[@"name"] UTF8String], key.UTF8String, [result[@"failures"][key] UTF8String]), failures++;
        if (failures) return 1;
        puts("PASS: Hide Toolbar checks wait out a stalled animation");
    }
    return 0;
}
