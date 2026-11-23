#import "Patches/CompactTabRows/CompactTabRows.h"

static NSString *currentChoice = @"small";
NSString *DPChoice(DPPatch *patch) { return currentChoice; }

static NSArray<NSView *> *foundShapes = @[];
static NSArray<NSView *> *DPTestFindViews(const char *className) {
    return strcmp(className, DPDiaTabShape) == 0 ? foundShapes : @[];
}

#define DPFindViews DPTestFindViews
#import "Patches/CompactTabRows/CompactTabRows.m"
#undef DPFindViews

@interface DPTestRimHighlightView : NSView {
@public
    CAShapeLayer *$__lazy_storage_$_shapeLayer;
    CGPathRef path;
}
@end

@implementation DPTestRimHighlightView
- (void)layout {
    if ($__lazy_storage_$_shapeLayer) $__lazy_storage_$_shapeLayer.path = path;
}
- (void)dealloc {
    if (path) CGPathRelease(path);
}
@end

static int failures;
static void Check(BOOL ok, NSString *msg) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", msg.UTF8String);
}

static CGPathRef MakeDiaContinuousPath(CGRect r) {
    CGFloat w = CGRectGetWidth(r), h = CGRectGetHeight(r), mid = h / 2;
    CGFloat c = MIN(15.28665, w / 2), a = MIN(10.8849, w / 2), b = MIN(8.68407, w / 2), k = MIN(6.31494, w / 2);
    CGFloat s1 = MIN(10.81523, mid), s2 = MIN(8.65782, mid), s3 = MIN(6.31494, mid);
    CGFloat e1 = MIN(3.72824, mid), e2 = MIN(1.69060, mid), e3 = MIN(0.74911, mid);
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, w, mid);
    CGPathAddLineToPoint(p, NULL, w, mid);
    CGPathAddCurveToPoint(p, NULL, w, h - s1, w, h - s2, w - e3, h - s3);
    CGPathAddCurveToPoint(p, NULL, w - e2, h - e1, w - e1, h - e2, w - k, h - e3);
    CGPathAddCurveToPoint(p, NULL, w - b, h, w - a, h, w - c, h);
    CGPathAddLineToPoint(p, NULL, c, h);
    CGPathAddCurveToPoint(p, NULL, a, h, b, h, k, h - e3);
    CGPathAddCurveToPoint(p, NULL, e1, h - e2, e2, h - e1, e3, h - s3);
    CGPathAddCurveToPoint(p, NULL, 0, h - s2, 0, h - s1, 0, mid);
    CGPathAddLineToPoint(p, NULL, 0, mid);
    CGPathAddCurveToPoint(p, NULL, 0, s1, 0, s2, e3, s3);
    CGPathAddCurveToPoint(p, NULL, e2, e1, e1, e2, k, e3);
    CGPathAddCurveToPoint(p, NULL, b, 0, a, 0, c, 0);
    CGPathAddLineToPoint(p, NULL, w - c, 0);
    CGPathAddCurveToPoint(p, NULL, w - a, 0, w - b, 0, w - k, e3);
    CGPathAddCurveToPoint(p, NULL, w - e1, e2, w - e2, e1, w - e3, s3);
    CGPathAddCurveToPoint(p, NULL, w, s2, w, s1, w, mid);
    CGPathCloseSubpath(p);
    return p;
}

static void FakeTabShapeLayout(NSView *self, SEL _cmd) {
    CGRect bounds = self.bounds;
    CGRect clamped = CGRectMake(0, 0, MAX(CGRectGetWidth(bounds), 50), MAX(CGRectGetHeight(bounds), 30));
    CGPathRef path = MakeDiaContinuousPath(clamped);

    CAShapeLayer *shapeLayer = DPIvarObject(self, "$__lazy_storage_$_shapeLayer");
    shapeLayer.frame = bounds;
    shapeLayer.path = path;

    CAShapeLayer *borderMask = DPIvarObject(self, "$__lazy_storage_$_gradientBorderMaskLayer");
    borderMask.frame = bounds;
    borderMask.path = path;

    CALayer *shadow = DPIvarObject(self, "$__lazy_storage_$_shadowLayer");
    NSEdgeInsets *outsets = DPIvar(self, "horizontalShadowOutsets");
    CGAffineTransform tx = CGAffineTransformMakeTranslation(outsets ? outsets->left : 0, 0);
    CGPathRef shadowPath = CGPathCreateCopyByTransformingPath(path, &tx);
    shadow.shadowPath = shadowPath;
    CGPathRelease(shadowPath);

    CAShapeLayer *bottomMask = DPIvarObject(self, "bottomShadowMaskLayer");
    bottomMask.bounds = CGRectMake(0, 0, CGRectGetWidth(bounds) + 40, CGRectGetHeight(bounds) + 20);
    CGMutablePathRef cutout = CGPathCreateMutable();
    CGPathAddRect(cutout, NULL, bottomMask.bounds);
    CGAffineTransform shift = CGAffineTransformMakeTranslation(20, 20);
    CGPathAddPath(cutout, &shift, path);
    bottomMask.path = cutout;
    CGPathRelease(cutout);

    NSView *rim = DPIvarObject(self, "rimHighlightView");
    void **slot = DPIvar(rim, "path");
    if (slot) {
        CGPathRef old = (CGPathRef)*slot;
        *slot = (void *)CGPathRetain(path);
        if (old) CGPathRelease(old);
    }
    rim.needsLayout = YES;
    CGPathRelease(path);
}

static void SetObjIvar(id obj, const char *name, id val) {
    objc_setAssociatedObject(obj, name, val, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *(void **)DPIvar(obj, name) = (__bridge void *)val;
}

static CGRect InnerHoleBox(CGPathRef cutout) {
    __block CGRect second = CGRectNull;
    __block int sub = 0;
    CGMutablePathRef part = CGPathCreateMutable();
    CGPathApplyWithBlock(cutout, ^(const CGPathElement *e) {
        if (e->type == kCGPathElementMoveToPoint) sub++;
        if (sub != 2) return;
        CGPoint *p = e->points;
        switch (e->type) {
            case kCGPathElementMoveToPoint: CGPathMoveToPoint(part, NULL, p[0].x, p[0].y); break;
            case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(part, NULL, p[0].x, p[0].y); break;
            case kCGPathElementAddQuadCurveToPoint: CGPathAddQuadCurveToPoint(part, NULL, p[0].x, p[0].y, p[1].x, p[1].y); break;
            case kCGPathElementAddCurveToPoint: CGPathAddCurveToPoint(part, NULL, p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y); break;
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(part); break;
        }
    });
    second = CGPathGetPathBoundingBox(part);
    CGPathRelease(part);
    return second;
}

static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.05; }

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        Class shapeCls = objc_allocateClassPair(NSView.class, DPDiaTabShape, 0);
        class_addIvar(shapeCls, "$__lazy_storage_$_shapeLayer", sizeof(void *), 3, "@");
        class_addIvar(shapeCls, "$__lazy_storage_$_gradientBorderMaskLayer", sizeof(void *), 3, "@");
        class_addIvar(shapeCls, "$__lazy_storage_$_shadowLayer", sizeof(void *), 3, "@");
        class_addIvar(shapeCls, "bottomShadowMaskLayer", sizeof(void *), 3, "@");
        class_addIvar(shapeCls, "rimHighlightView", sizeof(void *), 3, "@");
        class_addIvar(shapeCls, "shape", sizeof(uint8_t), 0, "C");
        class_addIvar(shapeCls, "horizontalShadowOutsets", sizeof(NSEdgeInsets), 3, "{NSEdgeInsets=dddd}");
        class_addMethod(shapeCls, @selector(layout), (IMP)FakeTabShapeLayout, "v@:");
        objc_registerClassPair(shapeCls);

        DPHook(DPDiaTabShape, @selector(layout), (IMP)DPTabShape_layout);

        NSView *tab = [[shapeCls alloc] initWithFrame:NSMakeRect(0, 0, 220, 27)];
        CAShapeLayer *shapeLayer = [CAShapeLayer layer];
        CAShapeLayer *borderMask = [CAShapeLayer layer];
        CALayer *shadow = [CALayer layer];
        CAShapeLayer *bottomMask = [CAShapeLayer layer];
        DPTestRimHighlightView *rim = [[DPTestRimHighlightView alloc] initWithFrame:NSMakeRect(0, 0, 220, 27)];
        CAShapeLayer *rimShape = [CAShapeLayer layer];
        rim->$__lazy_storage_$_shapeLayer = rimShape;
        SetObjIvar(tab, "$__lazy_storage_$_shapeLayer", shapeLayer);
        SetObjIvar(tab, "$__lazy_storage_$_gradientBorderMaskLayer", borderMask);
        SetObjIvar(tab, "$__lazy_storage_$_shadowLayer", shadow);
        SetObjIvar(tab, "bottomShadowMaskLayer", bottomMask);
        SetObjIvar(tab, "rimHighlightView", rim);
        *(uint8_t *)DPIvar(tab, "shape") = 0;
        *(NSEdgeInsets *)DPIvar(tab, "horizontalShadowOutsets") = NSEdgeInsetsMake(0, 6, 0, 6);
        foundShapes = @[ tab ];

        DPCompactTabRows.on = YES;
        currentChoice = @"small";
        for (int i = 0; i < 4; i++) [tab layout];
        CGRect sb = CGPathGetPathBoundingBox(shapeLayer.path);
        CGRect bb = CGPathGetPathBoundingBox(borderMask.path);
        CGRect shb = CGPathGetPathBoundingBox(shadow.shadowPath);
        CGRect hole = InnerHoleBox(bottomMask.path);
        CGRect rb = CGPathGetPathBoundingBox((CGPathRef)*(void **)DPIvar(rim, "path"));
        CGRect rsb = CGPathGetPathBoundingBox(rimShape.path);
        Check(Near(CGRectGetMinY(sb), 0) && Near(CGRectGetHeight(sb), 27) && Near(CGRectGetWidth(sb), 220), @"shapeLayer path fits 220x27");
        Check(Near(CGRectGetMinY(bb), 0) && Near(CGRectGetHeight(bb), 27), @"border mask path fits 27 pt so bottom border stays inside bounds");
        Check(Near(CGRectGetMinX(shb), 6) && Near(CGRectGetHeight(shb), 27), @"shadowPath keeps 6 pt horizontal outset and 27 pt height");
        Check(Near(CGRectGetMinY(hole), 20) && Near(CGRectGetHeight(hole), 27), @"bottomShadowMaskLayer hole fits 27 pt");
        Check(Near(CGRectGetHeight(rb), 27) && Near(CGRectGetHeight(rsb), 27), @"rimHighlightView path and shapeLayer fit 27 pt");
        [rim layout];
        Check(Near(CGRectGetHeight(CGPathGetPathBoundingBox(rimShape.path)), 27), @"RimHighlightView.layout keeps fitted 27 pt path");
        Check(!DPVerifyCompactTabRows(&DPCompactTabRows), @"verify passes when 27 pt Small shape is fitted");

        tab.frame = NSMakeRect(0, 0, 204, 27);
        [tab layout];
        sb = CGPathGetPathBoundingBox(shapeLayer.path);
        Check(Near(CGRectGetWidth(sb), 204) && Near(CGRectGetHeight(sb), 27), @"grouped child 204x27 fits cleanly");

        currentChoice = @"compact";
        tab.frame = NSMakeRect(0, 0, 220, 34);
        [tab layout];
        Check(Near(CGRectGetHeight(CGPathGetPathBoundingBox(shapeLayer.path)), 34), @"34 pt Compact pill stays 34 pt");

        currentChoice = @"small";
        tab.frame = NSMakeRect(0, 0, 220, 27);
        *(uint8_t *)DPIvar(tab, "shape") = 1;
        [tab layout];
        Check(Near(CGRectGetHeight(CGPathGetPathBoundingBox(shapeLayer.path)), 30), @"top tab bar shape == 1 is untouched");

        *(uint8_t *)DPIvar(tab, "shape") = 0;
        DPCompactTabRows.on = NO;
        [tab layout];
        Check(Near(CGRectGetHeight(CGPathGetPathBoundingBox(shapeLayer.path)), 30), @"patch off leaves Dia's path untouched");
        Check(!DPVerifyCompactTabRows(&DPCompactTabRows), @"verify passes when patch is off");

        DPCompactTabRows.on = YES;
        Check(DPVerifyCompactTabRows(&DPCompactTabRows) != nil, @"verify detects clipped 30 pt path inside 27 pt view");

        tab.frame = NSMakeRect(0, 0, 220, 12);
        [tab layout];
        Check(Near(CGRectGetHeight(CGPathGetPathBoundingBox(shapeLayer.path)), 12), @"collapse animation 12 pt falls back to valid 12 pt path");
        tab.frame = NSMakeRect(0, 0, 220, 0);
        [tab layout];
        Check(YES, @"zero-height bounds returns safely");
    }
    if (failures) return 1;
    puts("PASS: small tab shape path fits 27 pt bounds without clipping");
    return 0;
}
