#import "EdgeToEdge.h"

static int DPPointCount(CGPathElementType type) {
    switch (type) {
        case kCGPathElementAddCurveToPoint: return 3;
        case kCGPathElementAddQuadCurveToPoint: return 2;
        case kCGPathElementCloseSubpath: return 0;
        default: return 1;
    }
}

static CGFloat DPCornerEdge(CGFloat value, CGFloat low, CGFloat high, CGFloat extent) {
    if (value - low < extent) return low;
    if (high - value < extent) return high;
    return NAN;
}

// Keeps the same path elements so Dia's animations still interpolate.
CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale) {
    if (!path) return NULL;
    __block CGRect box = CGRectNull;
    __block int subpath = 0;
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        if (element->type == kCGPathElementMoveToPoint && !CGRectIsNull(box)) subpath++;
        for (int i = 0, count = DPPointCount(element->type); i < count && subpath == 0; i++) box = CGRectUnion(box, (CGRect){element->points[i], CGSizeZero});
    });
    CGMutablePathRef reshaped = CGPathCreateMutable();
    subpath = 0;
    __block BOOL started = NO;
    CGPoint (^move)(CGPoint) = ^CGPoint(CGPoint p) {
        if (subpath > 0) return p;
        CGFloat cx = DPCornerEdge(p.x, CGRectGetMinX(box), CGRectGetMaxX(box), extent);
        CGFloat cy = DPCornerEdge(p.y, CGRectGetMinY(box), CGRectGetMaxY(box), extent);
        if (isnan(cx) || isnan(cy)) return p;
        CGFloat scale = cx == CGRectGetMinX(box) ? leftScale : rightScale;
        return CGPointMake(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale);
    };
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        const CGPoint *p = element->points;
        switch (element->type) {
            case kCGPathElementMoveToPoint: {
                if (started) subpath++;
                started = YES;
                CGPoint a = move(p[0]);
                CGPathMoveToPoint(reshaped, NULL, a.x, a.y);
                break;
            }
            case kCGPathElementAddLineToPoint: {
                CGPoint a = move(p[0]);
                CGPathAddLineToPoint(reshaped, NULL, a.x, a.y);
                break;
            }
            case kCGPathElementAddQuadCurveToPoint: {
                CGPoint a = move(p[0]), b = move(p[1]);
                CGPathAddQuadCurveToPoint(reshaped, NULL, a.x, a.y, b.x, b.y);
                break;
            }
            case kCGPathElementAddCurveToPoint: {
                CGPoint a = move(p[0]), b = move(p[1]), c = move(p[2]);
                CGPathAddCurveToPoint(reshaped, NULL, a.x, a.y, b.x, b.y, c.x, c.y);
                break;
            }
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(reshaped); break;
        }
    });
    return (CGPathRef)CFAutorelease(reshaped);
}
