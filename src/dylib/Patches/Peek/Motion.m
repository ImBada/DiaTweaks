#import "Patches/Peek/Peek.h"
#import <objc/message.h>

static const CAFrameRateRange DPPeekFrameRate = {80, 120, 120};  // Without it, ProMotion starts these at 60 Hz.

CASpringAnimation *DPPeekSpring(NSString *keyPath, CFTimeInterval response, CGFloat dampingRatio) {
    CGFloat w = 2 * M_PI / response;
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:keyPath];
    spring.stiffness = w * w;
    spring.damping = 2 * dampingRatio * w;
    spring.duration = spring.settlingDuration;
    return spring;
}

static CGFloat DPPeekRemaining(CFTimeInterval t, CFTimeInterval response) {
    if (t <= 0) return 1;
    CGFloat w = 2 * M_PI / response;
    return (1 + w * t) * exp(-w * t);
}

typedef struct { CGFloat x, y, z; } DPPoint3D;
typedef struct { CGPoint from; DPPoint3D to; } DPMeshVertex;
typedef struct { unsigned int indices[4]; float w[4]; } DPMeshFace;

static id DPMesh(const CGPoint to[9]) {
    DPMeshVertex vertices[9];
    for (int i = 0; i < 9; i++) vertices[i] = (DPMeshVertex){{(i % 3) / 2.0, (i / 3) / 2.0}, {to[i].x, to[i].y, 0}};
    DPMeshFace faces[4];
    for (int f = 0; f < 4; f++) {
        unsigned int i = (f / 2) * 3 + f % 2;
        faces[f] = (DPMeshFace){{i, i + 1, i + 4, i + 3}, {0, 0, 0, 0}};
    }
    static Class meshClass;
    static SEL meshSel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        meshClass = NSClassFromString(@"CAMeshTransform");
        meshSel = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    });
    id (*make)(Class, SEL, NSUInteger, DPMeshVertex *, NSUInteger, DPMeshFace *, NSString *) = (void *)objc_msgSend;
    return make(meshClass, meshSel, 9, vertices, 4, faces, @"none");
}

static CAKeyframeAnimation *DPPeekKeyframes(NSString *keyPath, NSArray *values, NSArray *times, CFTimeInterval duration, BOOL opening) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
    animation.values = values;
    animation.keyTimes = times;
    animation.duration = duration;
    animation.fillMode = kCAFillModeBoth;
    animation.preferredFrameRateRange = DPPeekFrameRate;
    animation.removedOnCompletion = opening;  // Closing holds its end, or the card flashes back.
    return animation;
}

static void DPPeekTravel(DPPeekCard *peek, BOOL opening) {
    CFTimeInterval response = DPPeekResponse(), duration = 0, rows[3];
    CGFloat ay = 2 * MIN(1, MAX(0, NSMidY(peek.link) / MAX(1, NSHeight(peek.bounds)))) - 1;
    CGFloat g = !DPPeekGenie() ? 0 : ay >= 0 ? ay : 0.75 * ay;
    if (!opening) g = -g;
    for (int r = 0; r < 3; r++) {
        CGFloat v = r / 2.0, n = g < 0 ? 1 - sqrt(1 - v) : sqrt(v);
        rows[r] = response * (1 - 0.5 * g + g * n);
        duration = MAX(duration, DPPeekSpring(@"meshTransform", rows[r], 1).settlingDuration);
    }
    NSRect card = peek.cardFrame, outer = peek.card.frame, link = peek.link;
    NSRect source = NSMakeRect((NSMinX(link) - NSMinX(card)) / NSWidth(card), (NSMinY(link) - NSMinY(card)) / NSHeight(card),
                               NSWidth(link) / NSWidth(card), NSHeight(link) / NSHeight(card));
    NSRect inner = NSMakeRect((NSMinX(card) - NSMinX(outer)) / NSWidth(outer), (NSMinY(card) - NSMinY(outer)) / NSHeight(outer),
                              NSWidth(card) / NSWidth(outer), NSHeight(card) / NSHeight(outer));
    CGFloat radius = peek.clip.layer.cornerRadius, largest = MIN(NSWidth(card), NSHeight(card)) / 2;
    BOOL flipped = !peek.card.layer.geometryFlipped;
    int frames = MAX(60, (int)ceil(duration * 120));
    NSUInteger count = frames + 1;
    NSMutableArray *meshes = [NSMutableArray arrayWithCapacity:count], *radii = [NSMutableArray arrayWithCapacity:count],
                   *shadows = [NSMutableArray arrayWithCapacity:count], *fades = [NSMutableArray arrayWithCapacity:count],
                   *times = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i <= frames; i++) {
        CFTimeInterval t = duration * i / frames;
        CGPoint to[9];
        CGFloat away[3];
        for (int r = 0; r < 3; r++) {
            CGFloat remaining = DPPeekRemaining(t, rows[r]);
            away[r] = opening ? remaining : 1 - remaining;
            for (int c = 0; c < 3; c++) {
                CGFloat x = (c / 2.0 - NSMinX(inner)) / NSWidth(inner), y = (r / 2.0 - NSMinY(inner)) / NSHeight(inner);
                CGFloat px = NSMinX(inner) + (x + (NSMinX(source) + x * NSWidth(source) - x) * away[r]) * NSWidth(inner);
                CGFloat py = NSMinY(inner) + (y + (NSMinY(source) + y * NSHeight(source) - y) * away[r]) * NSHeight(inner);
                to[(flipped ? r : 2 - r) * 3 + c] = CGPointMake(px, flipped ? py : 1 - py);
            }
        }
        [meshes addObject:DPMesh(to)];
        CGFloat scale = MIN(1 + (NSWidth(source) - 1) * away[1], 1 + (NSHeight(source) - 1) * away[1]);
        [radii addObject:@(MIN(largest, (radius + (4 - radius) * away[1]) / MAX(0.01, scale)))];
        [shadows addObject:@(MAX(0, MIN(1, scale)))];
        CGFloat left = MAX(0, MIN(1, (1 - MIN(away[0], MIN(away[1], away[2]))) / 0.4));
        [fades addObject:@(left * left * (3 - 2 * left))];
        [times addObject:@((double)i / frames)];
    }
    [CATransaction setDisableActions:YES];
    [peek.card.layer addAnimation:DPPeekKeyframes(@"meshTransform", meshes, times, duration, opening) forKey:@"peek"];
    if (!opening) [peek.card.layer addAnimation:DPPeekKeyframes(@"opacity", fades, times, duration, opening) forKey:@"peekFade"];
    CAKeyframeAnimation *corners = DPPeekKeyframes(@"cornerRadius", radii, times, duration, opening);
    [peek.clip.layer addAnimation:corners forKey:@"peek"];
    [peek.shade.layer addAnimation:corners forKey:@"peek"];
    [peek.shade.layer addAnimation:DPPeekKeyframes(@"shadowOpacity", shadows, times, duration, opening) forKey:@"peekShadow"];
}

static CASpringAnimation *DPPeekDim(BOOL dimming) {
    CASpringAnimation *dim = DPPeekSpring(@"opacity", DPPeekResponse() * 0.314 / 0.24, 1);
    dim.fromValue = dimming ? @0 : @1;
    dim.toValue = dimming ? @1 : @0;
    dim.fillMode = kCAFillModeBoth;
    dim.preferredFrameRateRange = DPPeekFrameRate;
    dim.removedOnCompletion = dimming;
    return dim;
}

static void DPPeekRevealControls(NSView *controls) {
    controls.alphaValue = 1;
    for (NSButton *button in controls.subviews) {
        if (![button isKindOfClass:NSButton.class]) continue;
        CASpringAnimation *pop = DPPeekSpring(@"transform", 0.32, 0.7);
        pop.fromValue = [NSValue valueWithCATransform3D:DPPeekScaled(button, 0.4)];
        pop.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0;
        fade.toValue = @1;
        fade.duration = 0.14;
        CAAnimationGroup *enter = [CAAnimationGroup animation];
        enter.animations = @[pop, fade];
        enter.duration = pop.duration;
        enter.beginTime = CACurrentMediaTime() + button.tag * 0.05;
        enter.fillMode = kCAFillModeBackwards;
        enter.preferredFrameRateRange = DPPeekFrameRate;
        [button.layer addAnimation:enter forKey:@"peekEnter"];
    }
}

@interface DPPeekGrowth : NSObject
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval start, response, duration;
@property (nonatomic) NSUInteger settledFrames;
@property (nonatomic, copy) void (^done)(void);
@end

@implementation DPPeekGrowth
static char DPGrowthKey, DPInTimerKey;

+ (void)grow:(DPPeekCard *)peek done:(void (^)(void))done {
    DPPeekGrowth *growth = [DPPeekGrowth new];
    growth.peek = peek;
    growth.response = DPPeekResponse();
    growth.duration = DPPeekSpring(@"bounds", growth.response, 1).settlingDuration;
    growth.done = done;
    growth.start = CACurrentMediaTime();
    DPSet(peek, &DPGrowthKey, growth);  // The display link doesn't retain it.
    growth.link = [peek.window displayLinkWithTarget:growth selector:@selector(step)];
    growth.link.preferredFrameRateRange = DPPeekFrameRate;
    [growth.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    self.done = nil;
}

- (void)step {
    DPPeekCard *peek = self.peek;
    if (!peek || !peek.window || !peek.superview) {
        void (^done)(void) = self.done;
        [self stop];
        if (peek) DPSet(peek, &DPGrowthKey, nil);
        if (peek && done) done();
        return;
    }
    CFTimeInterval t = CACurrentMediaTime() - self.start;
    BOOL settled = t >= self.duration;
    if (peek.grown < 1) {
        peek.grown = settled ? 1 : 1 - DPPeekRemaining(t, self.response);
        peek.needsLayout = YES;
        [peek layoutSubtreeIfNeeded];
    }
    if (!settled) return;
    // Give the opening mesh and Chromium's full viewport time to present before handoff.
    if (peek.window && !peek.isHiddenOrHasHiddenAncestor && ([peek.card.layer animationForKey:@"peek"] || ++self.settledFrames < 3)) return;
    void (^done)(void) = self.done;
    [self stop];
    DPSet(peek, &DPGrowthKey, nil);
    if (done) done();
}
@end

@implementation DPPeekCard (Motion)

- (void)stopMotion {
    DPPeekGrowth *growth = DPGet(self, &DPGrowthKey);
    [growth stop];
    if (growth) DPSet(self, &DPGrowthKey, nil);
    NSTimer *inTimer = DPGet(self, &DPInTimerKey);
    [inTimer invalidate];
    if (inTimer) DPSet(self, &DPInTimerKey, nil);
}

- (void)animateIn {
    self.controls.alphaValue = self.card.alphaValue = self.dim.alphaValue = 0;
    CFTimeInterval start = CACurrentMediaTime();
    __weak DPPeekCard *weak = self;
    NSTimer *inTimer = [NSTimer scheduledTimerWithTimeInterval:1 / 120.0 repeats:YES block:^(NSTimer *timer) {
        DPPeekCard *peek = weak;
        if (!peek || peek.closing) {
            [timer invalidate];
            if (peek) DPSet(peek, &DPInTimerKey, nil);
            return;
        }
        if (![DPValueForKey(peek.page, @"isReadyToDisplay") boolValue] && CACurrentMediaTime() - start < 0.15) return;
        [timer invalidate];
        DPSet(peek, &DPInTimerKey, nil);
        if (peek.isHiddenOrHasHiddenAncestor) {
            peek.card.alphaValue = peek.dim.alphaValue = peek.controls.alphaValue = 1;
            return;
        }
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            if (!peek.closing) DPPeekRevealControls(peek.controls);
        }];
        DPPeekTravel(peek, YES);
        peek.card.alphaValue = peek.dim.alphaValue = 1;
        [peek.dim.layer addAnimation:DPPeekDim(YES) forKey:@"peek"];
        [CATransaction commit];
    }];
    DPSet(self, &DPInTimerKey, inTimer);
}

- (void)animateOut:(void (^)(void))completion {
    [CATransaction begin];
    [CATransaction setCompletionBlock:completion];
    if (self.card.alphaValue > 0) {
        [self.dim.layer addAnimation:DPPeekDim(NO) forKey:@"peek"];
        DPPeekTravel(self, NO);
    }
    [CATransaction commit];
}

- (void)animateExpand:(void (^)(void))completion {
    BOOL openingNotShown = self.card.alphaValue == 0;
    CALayer *dim = self.dim.layer.presentationLayer;
    CGFloat opacity = openingNotShown ? 0 : dim ? dim.opacity : self.dim.alphaValue;
    DPWithoutAnimation(^{
        // A promotion before the first Peek frame still starts its motion at the link.
        if (openingNotShown) DPPeekTravel(self, YES);
        self.card.alphaValue = self.dim.alphaValue = 1;
        CASpringAnimation *undim = DPPeekDim(NO);
        undim.fromValue = @(opacity);
        [self.dim.layer addAnimation:undim forKey:@"peek"];
    });
    [DPPeekGrowth grow:self done:completion];
}

@end
