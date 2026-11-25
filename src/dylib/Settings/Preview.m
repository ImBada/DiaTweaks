#import "Settings.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <VideoToolbox/VideoToolbox.h>
#import <sys/stat.h>

#ifndef DP_PREVIEWS
#define DP_PREVIEWS "https://raw.githubusercontent.com/wiki/JaceThings/DiaTweaks/previews/"
#endif

static NSNotificationName const DPTabLayoutMayHaveChanged = @"DPTabLayoutMayHaveChanged";

static void DPSidebarFooter_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarFooter_viewDidMoveToWindow, self);
    static BOOL pending;
    if (pending) return;
    pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending = NO;
        // Read the layout once per turn for every preview that is listening, not once per preview.
        [NSNotificationCenter.defaultCenter postNotificationName:DPTabLayoutMayHaveChanged object:DPTabLayout()];
    });
}

void DPInstallPreviews(void) {
    DPHook(DPDiaSidebarFooter, @selector(viewDidMoveToWindow), (IMP)DPSidebarFooter_viewDidMoveToWindow);
}

static NSURL *DPCachedPreview(NSString *name) {
    static NSURL *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        dir = [caches URLByAppendingPathComponent:@"DiaPatches/previews" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return [dir URLByAppendingPathComponent:name];
}

static NSArray<NSString *> *DPPreviewNames(NSString *key, NSString *layout) {
    NSString *other = [layout isEqual:@"vertical"] ? @"horizontal" : @"vertical";
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSString *prefix in @[layout, other])
        for (NSString *suffix in @[@"-onoff.webp", @".mp4", @".png"]) [names addObject:[NSString stringWithFormat:@"%@-%@%@", prefix, key, suffix]];
    return names;
}

static id DPDecodedPreview(NSURL *file, id (^decode)(void)) {
    static NSCache<NSString *, id> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 6;
    });
    struct stat info;
    if (stat(file.fileSystemRepresentation, &info)) return decode();
    NSString *key = [NSString stringWithFormat:@"%@ %lld %ld.%ld", file.path, info.st_size, info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    id decoded = [cache objectForKey:key];
    if (!decoded && (decoded = decode())) [cache setObject:decoded forKey:key];
    return decoded;
}

static BOOL DPSameFile(NSURL *file, NSData *data) {
    struct stat info;
    return !stat(file.fileSystemRepresentation, &info) && info.st_size == (off_t)data.length && [[NSData dataWithContentsOfURL:file] isEqualToData:data];
}

static BOOL DPIsPreview(NSData *data, NSString *name) {
    if (data.length < 8) return NO;
    if ([name hasSuffix:@".mp4"]) return !memcmp((const char *)data.bytes + 4, "ftyp", 4);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    BOOL decoded = image != NULL;
    CGImageRelease(image);
    if (source) CFRelease(source);
    return decoded;
}

static void DPFetchPreview(NSArray<NSString *> *names, void (^done)(NSURL *file, BOOL changed)) {
    if (!names.count) return done(nil, NO);
    NSURL *cached = DPCachedPreview(names[0]);
    NSURL *url = [NSURL URLWithString:[@DP_PREVIEWS stringByAppendingString:names[0]]];
    if (!url) return done(nil, NO);
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        BOOL preview = status == 200 && DPIsPreview(data, names[0]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || (status != 200 && status != 404)) return done(nil, NO);
            if (status == 404) {
                [NSFileManager.defaultManager removeItemAtURL:cached error:nil];
                return DPFetchPreview([names subarrayWithRange:NSMakeRange(1, names.count - 1)], done);
            }
            if (!preview) return done(nil, NO);
            BOOL changed = !DPSameFile(cached, data);
            if (changed) [data writeToURL:cached atomically:YES];
            done(cached, changed);
        });
    }] resume];
}

@interface DPPreviewLinkProxy : NSObject
@property (nonatomic, weak) DPPreviewView *target;
@end

@implementation DPPreviewLinkProxy
- (void)step:(CADisplayLink *)link {
    DPPreviewView *target = self.target;
    if (!target) return [link invalidate];
    [target performSelector:@selector(drawFrame)];
}
@end

@implementation DPPreviewView {
    NSString *_key, *_layout;
    NSArray<NSString *> *_names;
    NSURL *_shown;
    CALayer *_media;
    AVPlayer *_player;
    AVPlayerItemVideoOutput *_output;
    CADisplayLink *_link;
    NSArray *_states;
    NSTimer *_flip;
}

static BOOL DPIsLocalKey(NSString *key) {
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if ([DPPatches[i]->key isEqual:key]) return DPIsLocalPatch(DPPatches[i]);
    return NO;
}

- (instancetype)initWithKey:(NSString *)key {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _key = key;
    self.hidden = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutChanged:) name:DPTabLayoutMayHaveChanged object:nil];
    [self load];
    return self;
}

- (void)layoutChanged:(NSNotification *)notification {
    NSString *layout = [notification.object isKindOfClass:NSString.class] ? notification.object : DPTabLayout();
    [self load:layout];
}

- (void)load { [self load:DPTabLayout()]; }

- (void)load:(NSString *)layout {
    if ([layout isEqual:_layout]) return;
    _layout = layout;
    if (DPIsLocalKey(_key)) return;
    NSArray<NSString *> *names = _names = DPPreviewNames(_key, layout);
    for (NSString *name in names) {
        NSURL *cached = DPCachedPreview(name);
        if ([cached checkResourceIsReachableAndReturnError:nil]) return [self show:cached];
    }
    __weak DPPreviewView *weakSelf = self;
    DPFetchPreview(names, ^(NSURL *file, BOOL changed) {
        DPPreviewView *view = weakSelf;
        if (!view || view->_names != names) return;
        if (!file) {
            if (!view->_shown) [view show:nil];
        } else if (changed || ![file isEqual:view->_shown]) {
            [view show:file];
        }
    });
}

- (void)show:(NSURL *)file {
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [_media removeFromSuperlayer];
    [_player pause];
    _player = nil;
    _output = nil;
    _states = nil;
    [self updatePlayback];
    _media = nil;
    _shown = file;
    self.hidden = !file;
    if (!file) return;
    _media = [CALayer layer];
    _media.contentsGravity = kCAGravityResizeAspectFill;
    _media.frame = self.bounds;
    [self.layer addSublayer:_media];
    if ([file.lastPathComponent hasSuffix:@"-onoff.webp"]) {
        // Off in the top half, on in the bottom.
        _states = DPDecodedPreview(file, ^id {
            CGImageRef image = [[[NSImage alloc] initWithContentsOfURL:file] CGImageForProposedRect:NULL context:nil hints:nil];
            size_t width = image ? CGImageGetWidth(image) : 0, half = image ? CGImageGetHeight(image) / 2 : 0;
            if (!width || !half) return nil;
            id off = (__bridge_transfer id)CGImageCreateWithImageInRect(image, CGRectMake(0, 0, width, half));
            id on = (__bridge_transfer id)CGImageCreateWithImageInRect(image, CGRectMake(0, half, width, half));
            return off && on ? @[ off, on ] : nil;
        });
        if (!_states) return [self show:nil];
        [self showState];
        [self updatePlayback];
        return;
    }
    if (![file.pathExtension isEqualToString:@"mp4"]) {
        _media.contents = DPDecodedPreview(file, ^id { return [[NSImage alloc] initWithContentsOfURL:file]; });
        return;
    }
    // Not an AVPlayerLayer: macOS can hand that to the display hardware, which draws black bars at the preview's edges.
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:_output];
    _player = [AVPlayer playerWithPlayerItem:item];
    _player.muted = YES;
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rewind:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [self updatePlayback];
}

- (void)rewind:(NSNotification *)note {
    [_player seekToTime:kCMTimeZero];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidChangeOcclusionStateNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowWillCloseNotification object:nil];
    if (self.window) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatePlayback) name:NSWindowDidChangeOcclusionStateNotification object:self.window];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPlayback) name:NSWindowWillCloseNotification object:self.window];
    }
    [self updatePlayback];
}

- (void)stopTimers {
    [_link invalidate];
    _link = nil;
    [_flip invalidate];
    _flip = nil;
}

- (void)stopPlayback {
    [self stopTimers];
    [_player pause];
}

- (void)showState {
    if (!_states.count) return;
    DPWithoutAnimation(^{ self->_media.contents = self->_states[((unsigned long long)floor(NSDate.date.timeIntervalSince1970)) & 1]; });
}

- (void)updatePlayback {
    [self stopTimers];
    BOOL visible = (self.window.occlusionState & NSWindowOcclusionStateVisible) != 0;
    if (visible && _states) {
        [self showState];
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        __weak DPPreviewView *weakSelf = self;
        _flip = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSince1970:floor(now) + 1] interval:1 repeats:YES block:^(NSTimer *timer) {
            DPPreviewView *me = weakSelf;
            if (!me) return [timer invalidate];
            [me showState];
        }];
        [NSRunLoop.mainRunLoop addTimer:_flip forMode:NSRunLoopCommonModes];
    }
    if (!visible || !_player) return [_player pause];
    DPPreviewLinkProxy *proxy = [DPPreviewLinkProxy new];
    proxy.target = self;
    _link = [self displayLinkWithTarget:proxy selector:@selector(step:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [_player play];
}

- (void)drawFrame {
    CMTime time = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if (![_output hasNewPixelBufferForItemTime:time]) return;
    CVPixelBufferRef buffer = [_output copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
    if (!buffer) return;
    CGImageRef image = NULL;
    VTCreateCGImageFromCVPixelBuffer(buffer, NULL, &image);
    CVPixelBufferRelease(buffer);
    if (!image) return;
    id contents = (__bridge_transfer id)image;
    DPWithoutAnimation(^{ self->_media.contents = contents; });
}

- (void)updateLayer {
    [super updateLayer];
    self.layer.borderWidth = 1;
    self.layer.borderColor = NSColor.separatorColor.CGColor;
}

- (void)layout {
    [super layout];
    DPWithoutAnimation(^{ self->_media.frame = self.bounds; });
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_link invalidate];
    [_flip invalidate];
    [_player pause];
}
@end
