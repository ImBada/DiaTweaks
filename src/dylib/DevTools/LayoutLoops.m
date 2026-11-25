#import "DevTools/DevTools.h"
#include <sys/stat.h>

static const NSUInteger DPLoopLimit = 150;
static const NSUInteger DPMaxReports = 12, DPMaxFrames = 48;
static const off_t DPReportCap = 256 * 1024;
static NSMapTable<NSView *, NSMutableDictionary<NSString *, NSNumber *> *> *DPCounts;
static NSMutableSet<NSString *> *DPReported;
static NSString *DPReportPath;
static BOOL DPCounting;

typedef struct { char cls[64], superCls[64]; const void *view; NSRect from, to; } DPFrameChange;
enum { DPRecentCount = 24 };
static DPFrameChange DPRecent[DPRecentCount];
static NSUInteger DPRecentTotal;

static void DPRemember(NSView *view, NSRect from, NSRect to) {
    if (!NSThread.isMainThread || !view.window) return;
    DPFrameChange *change = &DPRecent[DPRecentTotal++ % DPRecentCount];
    strlcpy(change->cls, object_getClassName(view), sizeof change->cls);
    strlcpy(change->superCls, object_getClassName(view.superview), sizeof change->superCls);
    change->view = (__bridge const void *)view;
    change->from = from;
    change->to = to;
}

static void DPAppendReport(NSString *report) {
    struct stat info;
    const char *path = DPReportPath.fileSystemRepresentation;
    BOOL full = stat(path, &info) == 0 && info.st_size > DPReportCap;
    FILE *file = fopen(path, full ? "w" : "a");
    if (!file) return;
    NSData *data = [report dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, file);
    fclose(file);
}

static void DPReport(NSView *view, NSString *kind) {
    NSString *key = [NSString stringWithFormat:@"%s %@", object_getClassName(view), kind];
    if ([DPReported containsObject:key] || DPReported.count >= DPMaxReports) return;
    [DPReported addObject:key];
    NSMutableString *out = [NSMutableString stringWithFormat:@"== %@ %@ past %lu in one run loop turn\n", NSDate.date, key, (unsigned long)DPLoopLimit];
    for (NSView *up = view; up; up = up.superview) [out appendFormat:@"  in %s %@%@\n", object_getClassName(up), NSStringFromRect(up.frame), up.hidden ? @" hidden" : @""];
    [out appendString:@"  latest frame changes, oldest first:\n"];
    for (NSUInteger i = DPRecentTotal > DPRecentCount ? DPRecentTotal - DPRecentCount : 0; i < DPRecentTotal; i++) {
        DPFrameChange change = DPRecent[i % DPRecentCount];
        [out appendFormat:@"    %s %p %@ -> %@ (in %s)\n", change.cls, change.view, NSStringFromRect(change.from), NSStringFromRect(change.to), change.superCls];
    }
    NSArray<NSString *> *stack = NSThread.callStackSymbols;
    for (NSUInteger i = 0; i < MIN(stack.count, DPMaxFrames); i++) [out appendFormat:@"  %@\n", stack[i]];
    DPAppendReport(out);
}

static void DPCount(NSView *view, NSString *kind) {
    if (!DPCounting || !NSThread.isMainThread || !view.window) return;
    NSMutableDictionary *counts = [DPCounts objectForKey:view];
    if (!counts) [DPCounts setObject:counts = [NSMutableDictionary dictionary] forKey:view];
    NSUInteger n = [counts[kind] unsignedIntegerValue] + 1;
    counts[kind] = @(n);
    if (n == DPLoopLimit) DPReport(view, kind);
}

static void DPView_setNeedsLayout(NSView *self, SEL _cmd, BOOL needs) {
    if (needs) DPCount(self, @"needsLayout");
    DPCallOriginal(DPView_setNeedsLayout, self, needs);
}

static void DPView_setNeedsUpdateConstraints(NSView *self, SEL _cmd, BOOL needs) {
    if (needs) DPCount(self, @"needsUpdateConstraints");
    DPCallOriginal(DPView_setNeedsUpdateConstraints, self, needs);
}

static void DPView_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSRect from = self.frame;
    if (!NSEqualSizes(size, from.size)) {
        DPRemember(self, from, (NSRect){from.origin, size});
        DPCount(self, @"setFrameSize");
    }
    DPCallOriginal(DPView_setFrameSize, self, size);
}

static void DPView_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    NSRect from = self.frame;
    if (!NSEqualPoints(origin, from.origin)) {
        DPRemember(self, from, (NSRect){origin, from.size});
        DPCount(self, @"setFrameOrigin");
    }
    DPCallOriginal(DPView_setFrameOrigin, self, origin);
}

// Every NSView pays for these hooks, so they go in only for a developer who asks. Launch lays out in one long
// run loop turn, so counting starts after it.
void DPTraceLayoutLoops(void) {
    NSString *path = DPBesideDylib(@"layout-loops.txt");
    const char *wanted = getenv("DIAPATCH_LAYOUT_LOOPS");
    if (!wanted || !*wanted) {
        unlink(path.fileSystemRepresentation);
        return;
    }
    DPReportPath = path;
    DPCounts = [NSMapTable weakToStrongObjectsMapTable];
    DPReported = [NSMutableSet set];
    DPHookClass(NSView.class, @selector(setNeedsLayout:), (IMP)DPView_setNeedsLayout);
    DPHookClass(NSView.class, @selector(setNeedsUpdateConstraints:), (IMP)DPView_setNeedsUpdateConstraints);
    DPHookClass(NSView.class, @selector(setFrameSize:), (IMP)DPView_setFrameSize);
    DPHookClass(NSView.class, @selector(setFrameOrigin:), (IMP)DPView_setFrameOrigin);
    CFRunLoopObserverRef reset = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
        [DPCounts removeAllObjects];
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(), reset, kCFRunLoopCommonModes);
    DPOnLaunch(^{ DPCounting = YES; });
}
