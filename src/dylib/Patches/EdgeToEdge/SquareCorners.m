#import "EdgeToEdge.h"

static char DPPathKey, DPShadowPathKey, DPPastPathsKey, DPCornersTouchedKey, DPCornerCurveKey, DPControlCornerKey;
static NSMapTable<CALayer *, NSView *> *DPPathOwners;

typedef struct CACornerRadii { CGSize topLeft, topRight, bottomRight, bottomLeft; } CACornerRadii;

@interface CALayer (DPCornerRadii)
@property CACornerRadii cornerRadii;
@property(readonly) BOOL _usesCornerRadii;
@end

// All-zero cornerRadii fall back to cornerRadius, and some releases keep _usesCornerRadii set for them.
static BOOL DPRadiiEmpty(CACornerRadii radii) {
    return CGSizeEqualToSize(radii.topLeft, CGSizeZero) && CGSizeEqualToSize(radii.topRight, CGSizeZero)
        && CGSizeEqualToSize(radii.bottomRight, CGSizeZero) && CGSizeEqualToSize(radii.bottomLeft, CGSizeZero);
}

static void DPClearCornerRadii(CALayer *layer) {
    if (![layer respondsToSelector:@selector(setCornerRadii:)] || !layer._usesCornerRadii) return;
    CACornerRadii zero = {0};
    layer.cornerRadii = zero;
    if (!layer._usesCornerRadii || DPRadiiEmpty(layer.cornerRadii)) return;
    // Zero didn't take, so pin the corners to Dia's radius rather than leave them square.
    CGFloat r = layer.cornerRadius;
    CACornerRadii round = { { r, r }, { r, r }, { r, r }, { r, r } };
    layer.cornerRadii = round;
}

static void DPMaskCorners(NSView *container, CALayer *layer, CGFloat left, CGFloat right) {
    if ([layer respondsToSelector:@selector(setCornerRadii:)]) {
        layer.mask = nil;
        layer.maskedCorners = DPLeftCorners | DPRightCorners;
        // All-zero cornerRadii falls back to cornerRadius, so square stays a hair above zero.
        CGFloat l = MAX(0.01, layer.cornerRadius * (1 - left)), r = MAX(0.01, layer.cornerRadius * (1 - right));
        CACornerRadii radii = { { l, l }, { r, r }, { r, r }, { l, l } };
        DPAnimateLayer(container, layer, @"cornerRadii", [NSValue valueWithBytes:&radii objCType:@encode(CACornerRadii)]);
        return;
    }
    if ((left == 0 || left == 1) && (right == 0 || right == 1)) {
        layer.mask = nil;
        layer.maskedCorners = (left == 1 ? 0 : DPLeftCorners) | (right == 1 ? 0 : DPRightCorners);
        return;
    }
    CALayer *mask = layer.mask.sublayers.count == 2 ? layer.mask : [CALayer layer];
    if (mask != layer.mask) {
        for (int i = 0; i < 2; i++) {
            CALayer *half = [CALayer layer];
            half.backgroundColor = NSColor.blackColor.CGColor;
            half.cornerCurve = kCACornerCurveContinuous;
            half.maskedCorners = i ? DPRightCorners : DPLeftCorners;
            [mask addSublayer:half];
        }
    }
    CGRect bounds = layer.bounds;
    CGFloat half = CGRectGetWidth(bounds) / 2;
    mask.frame = bounds;
    mask.sublayers[0].frame = CGRectMake(0, 0, half + 1, CGRectGetHeight(bounds));
    mask.sublayers[1].frame = CGRectMake(half - 1, 0, half + 1, CGRectGetHeight(bounds));
    mask.sublayers[0].cornerRadius = layer.cornerRadius * (1 - left);
    mask.sublayers[1].cornerRadius = layer.cornerRadius * (1 - right);
    layer.mask = mask;
    layer.maskedCorners = 0;
}

static CGPathRef DPReshapePath(id owner, char *key, CGPathRef current, NSView *container, CGFloat base, CGFloat grow, CGFloat left, CGFloat right) {
    if (!current || CGRectGetWidth(CGPathGetBoundingBox(current)) < NSWidth(container.bounds) * 0.9) return NULL;
    if (fabs(grow - 1) < 0.001 && left == 0 && right == 0) {
        NSArray *saved = DPGet(owner, key);
        if (!saved) return NULL;
        CGPathRef dia = (__bridge CGPathRef)saved[0];
        BOOL match = [saved[1] isEqual:(__bridge id)current];
        DPSet(owner, key, nil);
        if (!DPGet(owner, &DPPathKey) && !DPGet(owner, &DPShadowPathKey)) {
            DPSet(owner, &DPPastPathsKey, nil);
            [DPPathOwners removeObjectForKey:owner];
        }
        return match && !CGPathEqualToPath(dia, current) ? (CGPathRef)CFAutorelease(CGPathCreateCopy(dia)) : NULL;
    }
    id dia = DPDiaValue(owner, key, (__bridge id)current);
    if (dia == (__bridge id)current) dia = CFBridgingRelease(CGPathCreateCopy(current));
    CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, grow * (1 - right), grow * (1 - left));
    DPOverride(owner, key, dia, (__bridge id)path);
    if (!DPPathOwners) DPPathOwners = [NSMapTable weakToWeakObjectsMapTable];
    [DPPathOwners setObject:container forKey:owner];
    // Dia's next animation may start from a path we set, so map each back to Dia's.
    NSMapTable *past = DPGet(owner, &DPPastPathsKey) ?: [NSMapTable strongToStrongObjectsMapTable];
    if (past.count > 8) [past removeAllObjects];
    [past setObject:dia forKey:(__bridge id)path];
    DPSet(owner, &DPPastPathsKey, past);
    return CGPathEqualToPath(path, current) ? NULL : path;
}

static void DPSetPath(CALayer *layer, NSString *key, CGPathRef path) {
    DPWithoutAnimation(^{ [layer setValue:(__bridge id)path forKey:key]; });
}

static CAShapeLayer *DPShapeOf(CALayer *sublayer) {
    if ([sublayer isKindOfClass:CAShapeLayer.class]) return (CAShapeLayer *)sublayer;
    return [sublayer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer.mask : nil;
}

static NSView *DPToolbarIn(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaToolbar); });
}

static void DPReshapePaths(NSView *container, CGFloat base, CGFloat grow, CGFloat left, CGFloat right) {
    for (NSView *sub in container.subviews)
        for (CALayer *sublayer in sub.layer.sublayers) {
            CAShapeLayer *shape = DPShapeOf(sublayer);
            CGPathRef path = DPReshapePath(shape, &DPPathKey, shape.path, container, base, grow, left, right);
            if (path) DPSetPath(shape, @"path", path);
            CGPathRef shadow = DPReshapePath(sublayer, &DPShadowPathKey, sublayer.shadowPath, container, base, grow, left, right);
            if (shadow) DPSetPath(sublayer, @"shadowPath", shadow);
        }
}

BOOL DPCornersRound(CALayer *layer, BOOL right) {
    if ([layer respondsToSelector:@selector(cornerRadii)] && layer._usesCornerRadii) {
        CACornerRadii radii = layer.cornerRadii;
        if (!DPRadiiEmpty(radii)) return (right ? radii.topRight.width : radii.topLeft.width) >= 0.5;
    }
    if (layer.mask) return layer.mask.sublayers[right].cornerRadius > 0;
    return layer.cornerRadius > 0 && (layer.maskedCorners & (right ? DPRightCorners : DPLeftCorners));
}

BOOL DPBesideSidebar(NSView *container) {
    return NSMinX(container.frame) > DPWindowPadding + 1 && !DPChatCard(container);
}

BOOL DPFullScreen(NSView *container) {
    return (container.window.styleMask & NSWindowStyleMaskFullScreen) && !DPChatCard(container);
}

static CALayer *DPCornerShape(NSView *container, CGFloat *base, CGFloat *grow, CGFloat *left, CGFloat *right) {
    CALayer *layer = DPRoundedContent(container).layer;
    if (!layer) return nil;
    CGFloat amount = DPEdgeToEdgeAmount(container);
    *right = DPFullScreen(container) ? amount : 0;
    BOOL beside = DPBesideSidebar(container);
    *left = beside ? DPSquareSidebarCorners.progress * amount : *right;
    CGFloat growth = DPWindowCornerGrowth(container.window);
    if (growth > 0 && layer.cornerRadius > 0 && beside) *left = 1 - (1 - *left) * (layer.cornerRadius - growth) / layer.cornerRadius;
    *base = DPBaseCornerRadius(container) ?: layer.cornerRadius;
    *grow = *base > 0 ? layer.cornerRadius / *base : 1;
    return layer;
}

static void DPRestorePath(id owner, char *key, NSString *prop) {
    if (!owner) return;
    NSArray *saved = DPGet(owner, key);
    if (!saved) return;
    CGPathRef dia = (__bridge CGPathRef)saved[0];
    id current = [owner valueForKey:prop];
    BOOL match = [saved[1] isEqual:current];
    DPSet(owner, key, nil);
    DPSet(owner, &DPPastPathsKey, nil);
    [DPPathOwners removeObjectForKey:owner];
    if (match && dia && (!current || !CGPathEqualToPath(dia, (__bridge CGPathRef)current))) DPSetPath(owner, prop, dia);
}

static void DPRestoreCornerCurve(CALayer *layer) {
    CALayerCornerCurve saved = DPGet(layer, &DPCornerCurveKey);
    if (!saved) return;
    DPSet(layer, &DPCornerCurveKey, nil);
    if (layer.cornerCurve != saved) layer.cornerCurve = saved;
}

static void DPRestoreSquareCorners(NSView *container, CALayer *layer) {
    DPSet(container, &DPCornersTouchedKey, nil);
    DPWithoutAnimation(^{
        DPRestoreCornerCurve(layer);
        CALayer *card = DPChatCard(container).layer;
        if (card) DPRestoreCornerCurve(card);
        DPClearCornerRadii(layer);
        if (layer.mask) layer.mask = nil;
        if (layer.maskedCorners != (DPLeftCorners | DPRightCorners)) layer.maskedCorners = DPLeftCorners | DPRightCorners;
        for (NSView *sub in container.subviews)
            for (CALayer *sublayer in sub.layer.sublayers) {
                DPRestorePath(DPShapeOf(sublayer), &DPPathKey, @"path");
                DPRestorePath(sublayer, &DPShadowPathKey, @"shadowPath");
            }
        NSView *content = DPRoundedContent(container);
        NSView *bar = DPToolbarIn(content);
        if (bar && [content.layer respondsToSelector:@selector(setCornerRadii:)]) {
            DPFindView(bar, ^BOOL(NSView *view) {
                CALayer *ctrl = view.layer;
                if (!DPGet(ctrl, &DPControlCornerKey)) return NO;
                DPSet(ctrl, &DPControlCornerKey, nil);
                DPClearCornerRadii(ctrl);
                return NO;
            });
        }
    });
}

void DPRoundCornerControls(NSView *container) {
    if (!DPEdgeToEdgeActive()) return;
    NSView *content = DPRoundedContent(container);
    NSView *bar = DPToolbarIn(content);
    if (!bar || ![content.layer respondsToSelector:@selector(cornerRadii)]) return;
    CACornerRadii page = content.layer.cornerRadii;
    CGFloat width = NSWidth(content.bounds);
    DPFindView(bar, ^BOOL(NSView *view) {
        CALayer *layer = view.layer;
        CGFloat dia = layer.cornerRadius;
        if (view == bar || dia <= 0 || view.isHiddenOrHasHiddenAncestor) return NO;
        NSRect rect = [view convertRect:view.bounds toView:content];
        CGFloat top = content.isFlipped ? NSMinY(rect) : NSHeight(content.bounds) - NSMaxY(rect), left = NSMinX(rect), right = width - NSMaxX(rect);
        CGFloat topLeft = top < 12 && left < 12 ? MAX(dia, page.topLeft.width - MAX(top, left)) : dia;
        CGFloat topRight = top < 12 && right < 12 ? MAX(dia, page.topRight.width - MAX(top, right)) : dia;
        if (topLeft == dia && topRight == dia && !layer._usesCornerRadii) return NO;
        CGSize l = CGSizeMake(topLeft, topLeft), r = CGSizeMake(topRight, topRight), d = CGSizeMake(dia, dia);
        CACornerRadii radii = layer.contentsAreFlipped ? (CACornerRadii){ d, d, r, l } : (CACornerRadii){ l, r, d, d };
        DPSet(layer, &DPControlCornerKey, @YES);
        DPAnimateLayer(container, layer, @"cornerRadii", [NSValue valueWithBytes:&radii objCType:@encode(CACornerRadii)]);
        return NO;
    });
}

static void DPUseContinuousCurve(CALayer *layer) {
    if (!layer || layer.cornerCurve == kCACornerCurveContinuous) return;
    if (!DPGet(layer, &DPCornerCurveKey)) DPSet(layer, &DPCornerCurveKey, layer.cornerCurve ?: kCACornerCurveCircular);
    layer.cornerCurve = kCACornerCurveContinuous;
}

void DPApplySquareCorners(NSView *container) {
    CGFloat base, grow, left, right;
    CALayer *layer = DPCornerShape(container, &base, &grow, &left, &right);
    if (!layer) return;
    if (!DPEdgeToEdgeActive()) {
        if (DPGet(container, &DPCornersTouchedKey)) DPRestoreSquareCorners(container, layer);
        return;
    }
    DPSet(container, &DPCornersTouchedKey, @YES);
    DPWithoutAnimation(^{
        DPUseContinuousCurve(layer);
        DPUseContinuousCurve(DPChatCard(container).layer);
        DPMaskCorners(container, layer, left, right);
        DPReshapePaths(container, base, grow, left, right);
    });
    DPRoundCornerControls(container);
}

CGPathRef DPReshapeSetPath(CALayer *layer, BOOL shadow, CGPathRef path) {
    NSView *container = [DPPathOwners objectForKey:layer];
    if (!container || !path || [DPGet(layer, &DPPastPathsKey) objectForKey:(__bridge id)path]) return path;
    CGFloat base, grow, left, right;
    if (!DPCornerShape(container, &base, &grow, &left, &right)) return path;
    return DPReshapePath(layer, shadow ? &DPShadowPathKey : &DPPathKey, path, container, base, grow, left, right) ?: path;
}

CAAnimation *DPReshapeDiaAnimation(CALayer *layer, CAAnimation *animation) {
    CABasicAnimation *move = (CABasicAnimation *)animation;
    if (![move isKindOfClass:CABasicAnimation.class] || !([move.keyPath isEqual:@"path"] || [move.keyPath isEqual:@"shadowPath"])) return animation;
    NSView *container = [DPPathOwners objectForKey:layer];
    if (!container || !DPWindowCornerGrowth(container.window)) return animation;
    CGFloat base, grow, left, right;
    if (!DPCornerShape(container, &base, &grow, &left, &right)) return animation;
    CABasicAnimation *reshaped = [move copy];
    NSMapTable *past = DPGet(layer, &DPPastPathsKey);
    for (NSString *end in @[ @"fromValue", @"toValue" ]) {
        id value = [move valueForKey:end];
        CGPathRef path = (__bridge CGPathRef)([past objectForKey:value] ?: value);
        if (path && CGRectGetWidth(CGPathGetBoundingBox(path)) >= NSWidth(container.bounds) * 0.9)
            [reshaped setValue:(__bridge id)DPReshapeCorners(path, base * 1.6, grow * (1 - right), grow * (1 - left)) forKey:end];
    }
    return reshaped;
}

static NSString *DPVerifySquareCorners(DPPatch *patch) {
    for (NSView *container in DPFindViews(DPDiaContentContainer)) {
        CALayer *layer = DPRoundedContent(container).layer;
        if (!layer) return @"no rounded web content found";
        if (!DPBesideSidebar(container)) continue;
        BOOL square = patch->on && DPEdgeToEdgeAmount(container) > 0.5;
        if (DPCornersRound(layer, NO) == square) return square ? @"corners by the sidebar are round" : @"corners by the sidebar are square";
    }
    return nil;
}

DP_PATCH(DPSquareSidebarCorners) {
    .key = @"squareSidebarCorners",
    .defaultOn = YES,
    .order = 20,
    .title = @"Square Corners Next to Sidebar",
    .detail = @"Give web pages square corners where they meet the sidebar.",
    .symbol = @"square.fill",
    .tint = @"systemBlueColor",
    .requires = @"edgeToEdge",
    .relayout = DPRelayoutContainers,
    .verify = DPVerifySquareCorners,
};
