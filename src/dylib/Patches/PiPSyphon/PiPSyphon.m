#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#import <Syphon/SyphonMetalServer.h>

// Personal and experimental. Chromium normally shows PiP video through a CALayerHost that points into its GPU process,
// so Dia's own process never sees a pixel. With RemoteCoreAnimationAPI off, Chromium hands every composited frame to
// Dia as an IOSurface that it sets as a layer's contents. This catches those frames and publishes them through Syphon.
// The server starts with Dia and stays up between PiPs, so Syphon clients keep their connection. Syphon's server
// code is built in from src/vendor/Syphon.

#define DPPiPWindowContent "_TtC16PictureInPicture16PIPWindowContent"
#define DPPiPController "ArcWebContentsMediaSessionPiPController"
#define DPFramePrefix "DPPiPFrameLayer_"

extern DPPatch DPPiPSyphon;

static BOOL gFlagged;  // whether this launch asked Chromium to drop remote Core Animation
static NSHashTable<NSView *> *gContents;
static __weak NSView *gVideoView;
static __weak CALayer *gFrameLayer;
static Class gFrameBase;
static NSTimer *gPollTimer, *gWatchTimer;
static id<MTLDevice> gDevice;
static id<MTLCommandQueue> gQueue;
static SyphonMetalServer *gServer;
static NSMutableDictionary<NSNumber *, id<MTLTexture>> *gTextures;
static BOOL gFlip;

static BOOL DPIsSurface(id contents) {
    return contents && CFGetTypeID((__bridge CFTypeRef)contents) == IOSurfaceGetTypeID();
}

#pragma mark Publishing

static BOOL DPEnsureServer(void) {
    if (gServer) return YES;
    static BOOL failed;
    if (failed) return NO;
    failed = YES;
    gDevice = gDevice ?: MTLCreateSystemDefaultDevice();
    gQueue = gQueue ?: [gDevice newCommandQueue];
    gServer = gQueue ? [[SyphonMetalServer alloc] initWithName:@"PiP" device:gDevice options:nil] : nil;
    if (!gServer) {
        NSLog(@"DiaPatches: can't start a Syphon server");
        return NO;
    }
    // Syphon surfaces are bottom-up, as OpenGL reads them, but Chromium's IOSurfaces are top-down.
    id flipped = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] objectForKey:@"pipSyphonFlipped"];
    gFlip = flipped ? [flipped boolValue] : YES;
    failed = NO;
    return YES;
}

static void DPStopServer(void) {
    [gServer stop];
    gServer = nil;
}

static MTLPixelFormat DPMetalFormat(OSType format) {
    switch (format) {
    case 'BGRA': return MTLPixelFormatBGRA8Unorm;
    case 'RGBA': return MTLPixelFormatRGBA8Unorm;
    case 'RGhA': return MTLPixelFormatRGBA16Float;
    case 'l10r': return MTLPixelFormatBGR10A2Unorm;
    default: return MTLPixelFormatInvalid;
    }
}

static id<MTLTexture> DPTexture(IOSurfaceRef surface) {
    NSNumber *key = @((uintptr_t)surface);
    id<MTLTexture> texture = gTextures[key];
    size_t width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface);
    MTLPixelFormat format = DPMetalFormat(IOSurfaceGetPixelFormat(surface));
    if (texture && texture.width == width && texture.height == height && texture.pixelFormat == format) return texture;
    if (format == MTLPixelFormatInvalid) return nil;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:width height:height mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    texture = [gDevice newTextureWithDescriptor:descriptor iosurface:surface plane:0];
    if (!texture) return nil;
    // Chromium cycles through a few surfaces; drop stale ones when it makes new ones, as it does on a resize.
    if (gTextures.count >= 8) [gTextures removeAllObjects];
    gTextures[key] = texture;
    return texture;
}

static void DPPublish(id contents) {
    if (!DPPiPSyphon.on || !DPIsSurface(contents) || !DPEnsureServer()) return;
    id<MTLTexture> texture = DPTexture((__bridge IOSurfaceRef)contents);
    if (!texture) return;
    id<MTLCommandBuffer> buffer = [gQueue commandBuffer];
    [gServer publishFrameTexture:texture onCommandBuffer:buffer imageRegion:NSMakeRect(0, 0, texture.width, texture.height) flipped:gFlip];
    [buffer commit];
}

#pragma mark Catching frames

// Chromium either sets a new IOSurface or, for the same one again, calls -setContentsChanged.
static Class DPFrameSuper(id self) {
    for (Class cls = object_getClass(self); cls; cls = class_getSuperclass(cls))
        if (!strncmp(class_getName(cls), DPFramePrefix, strlen(DPFramePrefix))) return class_getSuperclass(cls);
    return Nil;
}

static void DPFrame_setContents(CALayer *self, SEL _cmd, id contents) {
    struct objc_super base = {self, DPFrameSuper(self)};
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&base, _cmd, contents);
    DPPublish(contents);
}

static void DPFrame_contentsChanged(CALayer *self, SEL _cmd) {
    struct objc_super base = {self, DPFrameSuper(self)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&base, _cmd);
    DPPublish(self.contents);
}

static Class DPFrameClass(Class base) {
    NSString *name = [@DPFramePrefix stringByAppendingString:NSStringFromClass(base)];
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    cls = objc_allocateClassPair(base, name.UTF8String, 0);
    class_addMethod(cls, @selector(setContents:), (IMP)DPFrame_setContents, "v@:@");
    SEL changed = NSSelectorFromString(@"setContentsChanged");
    if ([base instancesRespondToSelector:changed]) class_addMethod(cls, changed, (IMP)DPFrame_contentsChanged, "v@:");
    objc_registerClassPair(cls);
    return cls;
}

static void DPDetach(void) {
    CALayer *layer = gFrameLayer;
    if (layer && gFrameBase && !strncmp(object_getClassName(layer), DPFramePrefix, strlen(DPFramePrefix))) object_setClass(layer, gFrameBase);
    [gPollTimer invalidate];
    gPollTimer = nil;
    [gTextures removeAllObjects];  // they keep Chromium's surfaces, several MB each, alive
    gFrameLayer = nil;
    gFrameBase = Nil;
}

static void DPAttach(CALayer *layer) {
    DPDetach();
    gFrameLayer = layer;
    Class real = object_getClass(layer);
    if (real == layer.class) {
        gFrameBase = real;
        object_setClass(layer, DPFrameClass(real));
    } else {
        // Someone else already swapped its class (KVO, say): poll it instead of stacking on theirs.
        gPollTimer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) { DPPublish(gFrameLayer.contents); }];
        [NSRunLoop.mainRunLoop addTimer:gPollTimer forMode:NSRunLoopCommonModes];
    }
    DPPublish(layer.contents);
}

static CALayer *DPSurfaceLayer(CALayer *layer) {
    if (DPIsSurface(layer.contents)) return layer;
    for (CALayer *sub in layer.sublayers) {
        CALayer *found = DPSurfaceLayer(sub);
        if (found) return found;
    }
    return nil;
}

static NSView *DPFrameView(NSWindow *window) { return window.contentView.superview ?: window.contentView; }

// AppKit puts a root layer above the frame view's, so look for the frame view's on the way up rather than at the top.
static BOOL DPLayerIn(CALayer *layer, NSWindow *window) {
    CALayer *frame = DPFrameView(window).layer;
    for (CALayer *up = layer; up; up = up.superlayer)
        if (up == frame) return YES;
    return NO;
}

static BOOL DPFindIn(NSWindow *window) {
    NSView *video = gVideoView;
    CALayer *layer = video.window == window ? DPSurfaceLayer(video.layer) : nil;
    layer = layer ?: DPSurfaceLayer(DPFrameView(window).layer);
    if (!layer) return NO;
    if (layer != gFrameLayer) DPAttach(layer);
    return YES;
}

// Chromium sets the first frame a moment after the PiP window appears.
static void DPFind(NSWindow *window, NSUInteger attempt) {
    if (!DPPiPSyphon.on || !window || DPFindIn(window) || attempt == 15) return;
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{ DPFind(weak, attempt + 1); });
}

// Chromium can replace the frame layer without the PiP window moving, as when its GPU process restarts.
static void DPWatch(void) {
    CALayer *layer = gFrameLayer;
    for (NSView *content in gContents)
        if (layer && content.window && DPLayerIn(layer, content.window)) return;
    if (layer) DPDetach();
    for (NSView *content in gContents)
        if (content.window && DPFindIn(content.window)) return;
}

#pragma mark Hooks and patch

static void DPContent_moved(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_moved, self);
    if (!self.window) return;
    [gContents addObject:self];
    if (DPPiPSyphon.on) DPFind(self.window, 0);
}

static NSView *DPController_videoView(id self, SEL _cmd) {
    NSView *view = DPCallOriginal(DPController_videoView, self);
    if (view) gVideoView = view;
    return view;
}

static void DPStart(void) {
    DPEnsureServer();
    if (!gWatchTimer) {
        gWatchTimer = [NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) { DPWatch(); }];
        [NSRunLoop.mainRunLoop addTimer:gWatchTimer forMode:NSRunLoopCommonModes];
    }
    for (NSView *content in DPFindViews(DPPiPWindowContent)) [gContents addObject:content];
    for (NSView *content in gContents) if (content.window) DPFind(content.window, 0);
}

static void DPStop(void) {
    [gWatchTimer invalidate];
    gWatchTimer = nil;
    DPDetach();
    DPStopServer();
}

static void DPInstallPiPSyphon(void) {
    gContents = [NSHashTable weakObjectsHashTable];
    gTextures = [NSMutableDictionary dictionary];
    DPHook(DPPiPWindowContent, @selector(viewDidMoveToWindow), (IMP)DPContent_moved);
    DPHook(DPPiPController, @selector(videoView), (IMP)DPController_videoView);
    gFlagged = DPPiPSyphon.on;
    if (!gFlagged) return;
    DPAddLaunchFlag(@"--disable-features=RemoteCoreAnimationAPI");
    DPOnLaunch(^{ DPStart(); });  // a patch that's on at launch gets no apply call
}

static void DPApplyPiPSyphon(DPPatch *patch) {
    if (patch->on) DPStart();
    else DPStop();
    if (patch->on == gFlagged || patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to send PiP to Syphon" : @"Relaunch Dia to restore its usual rendering";
    alert.informativeText = patch->on ? @"Chromium only hands PiP frames to Dia when it starts without remote Core Animation."
                                      : @"Until then, Dia keeps rendering without remote Core Animation.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPPiPSyphon) {
    .key = @"pipSyphon",
    .order = 113,
    .section = @"Picture in Picture",
    .title = @"Send PiP to Syphon",
    .detail = @"Publish the Picture in Picture video as a Syphon server named PiP, which stays up between videos. While on, Dia renders without remote Core Animation, which costs power. Experimental.",
    .symbol = @"pip",
    .tint = @"systemRedColor",
    .install = DPInstallPiPSyphon,
    .apply = DPApplyPiPSyphon,
};
