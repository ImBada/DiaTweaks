#import "Patches/Peek/Peek.h"

static char DPPeekChatKVOContext;

static id DPPeekChatTargetFor(id webContents) {
    if (!DPPeek.on || DPPeekFindingLink || !webContents) return nil;
    for (DPPeekCard *peek in DPPeekAllCards(nil)) {
        if (peek.closing || !peek.window || peek.isHiddenOrHasHiddenAncestor) continue;
        if (peek.source == webContents && peek.page && peek.page != webContents) return peek.page;
    }
    return nil;
}

// Notifies Dia's selected-text KVO and bumps PrefetchCacheEntry's input timestamp so cached scrapes refresh.
static void DPPeekNotifySource(id source, BOOL selection) {
    if (!source) return;
    if (selection) {
        [source willChangeValueForKey:@"selectedText"];
        [source didChangeValueForKey:@"selectedText"];
    }
    [source willChangeValueForKey:@"inputEvent"];
    [source didChangeValueForKey:@"inputEvent"];
}

@interface DPPeekChatBridge : NSObject
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, strong) id page;
@property (nonatomic, weak) id source;
@property (nonatomic, copy) NSArray<NSString *> *keys;
- (void)detach;
@end

@implementation DPPeekChatBridge

- (instancetype)initWithPeek:(DPPeekCard *)peek {
    if (!(self = [super init])) return nil;
    _peek = peek;
    _page = peek.page;
    _source = peek.source;
    NSMutableArray<NSString *> *observed = [NSMutableArray array];
    for (NSString *key in @[ @"selectedText", @"isLoading", @"url" ]) {
        if (![_page respondsToSelector:NSSelectorFromString(key)]) continue;
        [_page addObserver:self forKeyPath:key options:0 context:&DPPeekChatKVOContext];
        [observed addObject:key];
    }
    _keys = observed;
    return self;
}

- (void)handleKey:(NSString *)keyPath {
    id page, source;
    @synchronized (self) {
        page = _page;
        source = _source;
    }
    DPPeekCard *peek = self.peek;
    if (!DPPeek.on || !page || !source || !peek || peek.closing || peek.isHiddenOrHasHiddenAncestor) return;
    if ([keyPath isEqualToString:@"isLoading"] && [DPValueForKey(page, @"isLoading") boolValue]) return;
    DPPeekNotifySource(source, [keyPath isEqualToString:@"selectedText"]);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &DPPeekChatKVOContext) return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    if (NSThread.isMainThread) [self handleKey:keyPath];
    else {
        __weak DPPeekChatBridge *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf handleKey:keyPath]; });
    }
}

- (void)detach {
    id page;
    NSArray<NSString *> *keys;
    @synchronized (self) {
        page = _page;
        keys = _keys;
        _page = nil;
        _keys = nil;
        _source = nil;
    }
    for (NSString *key in keys) [page removeObserver:self forKeyPath:key context:&DPPeekChatKVOContext];
}

- (void)dealloc { [self detach]; }

@end

void DPPeekChatAttach(DPPeekCard *peek) {
    DPPeekChatDetachQuiet(peek);
    if (!DPPeek.on || !peek || peek.closing || !peek.page || !peek.source || peek.page == peek.source) return;
    peek.chatBridge = [[DPPeekChatBridge alloc] initWithPeek:peek];
    DPPeekNotifySource(peek.source, YES);
}

void DPPeekChatDetachBridge(id bridge) {
    if ([bridge isKindOfClass:DPPeekChatBridge.class]) [(DPPeekChatBridge *)bridge detach];
}

void DPPeekChatDetachQuiet(DPPeekCard *peek) {
    DPPeekChatBridge *bridge = peek.chatBridge;
    if (!bridge) return;
    peek.chatBridge = nil;
    [bridge detach];
}

void DPPeekChatDetach(DPPeekCard *peek) {
    DPPeekChatBridge *bridge = peek.chatBridge;
    if (!bridge) return;
    BOOL wasHidden = peek.isHiddenOrHasHiddenAncestor;
    id source = peek.source;
    DPPeekChatDetachQuiet(peek);
    if (!wasHidden) DPPeekNotifySource(source, YES);
}

void DPPeekChatVisibilityDidChange(DPPeekCard *peek) {
    if (!DPPeek.on || !peek || peek.closing || !peek.source) return;
    DPPeekNotifySource(peek.source, YES);
}

static void DPPageExtract_get(id self, SEL _cmd, id webContents, id completion) {
    id target = DPPeekChatTargetFor(webContents) ?: webContents;
    DPCallOriginal(DPPageExtract_get, self, target, completion);
}

static void DPWeb_execReason(id self, SEL _cmd, NSString *script, NSString *reason, id completion) {
    id target = DPPeekChatTargetFor(self) ?: self;
    DPCallOriginal(DPWeb_execReason, target, script, reason, completion);
}

static void DPWeb_exec(id self, SEL _cmd, NSString *script, id completion) {
    id target = DPPeekChatTargetFor(self) ?: self;
    DPCallOriginal(DPWeb_exec, target, script, completion);
}

static NSString *DPWeb_selectedText(id self, SEL _cmd) {
    id target = DPPeekChatTargetFor(self) ?: self;
    return DPCallOriginal(DPWeb_selectedText, target);
}

static void DPWeb_captureViewport(id self, SEL _cmd, id completion) {
    id target = DPPeekChatTargetFor(self) ?: self;
    DPCallOriginal(DPWeb_captureViewport, target, completion);
}

static void DPWeb_captureFullPage(id self, SEL _cmd, id completion) {
    id target = DPPeekChatTargetFor(self) ?: self;
    DPCallOriginal(DPWeb_captureFullPage, target, completion);
}

static void DPWeb_captureRegion(id self, SEL _cmd, CGRect region, id completion) {
    id target = DPPeekChatTargetFor(self) ?: self;
    DPCallOriginal(DPWeb_captureRegion, target, region, completion);
}

static NSString *DPWeb_mimeType(id self, SEL _cmd) {
    id target = DPPeekChatTargetFor(self) ?: self;
    return DPCallOriginal(DPWeb_mimeType, target);
}

static id DPWeb_pdfController(id self, SEL _cmd) {
    id target = DPPeekChatTargetFor(self) ?: self;
    return DPCallOriginal(DPWeb_pdfController, target);
}

static NSString *DPWeb_a11yRoot(id self, SEL _cmd) {
    id target = DPPeekChatTargetFor(self) ?: self;
    return DPCallOriginal(DPWeb_a11yRoot, target);
}

static id DPWeb_a11yTree(id self, SEL _cmd, NSString *treeId) {
    id target = DPPeekChatTargetFor(self) ?: self;
    return DPCallOriginal(DPWeb_a11yTree, target, treeId);
}

void DPPeekInstallChatContext(void) {
    DPHook(DPDiaPageContentExtraction, @selector(getExtractedContentForWebContents:completion:), (IMP)DPPageExtract_get);
    DPHook(DPDiaWebContents, @selector(executeJavascript:reason:completion:), (IMP)DPWeb_execReason);
    DPHook(DPDiaWebContents, @selector(executeJavascript:completion:), (IMP)DPWeb_exec);
    DPHook(DPDiaWebContents, @selector(selectedText), (IMP)DPWeb_selectedText);
    DPHook(DPDiaWebContents, @selector(captureViewport:), (IMP)DPWeb_captureViewport);
    DPHook(DPDiaWebContents, @selector(captureFullPage:), (IMP)DPWeb_captureFullPage);
    DPHook(DPDiaWebContents, @selector(captureRegion:completion:), (IMP)DPWeb_captureRegion);
    DPHook(DPDiaWebContents, @selector(contentsMimeType), (IMP)DPWeb_mimeType);
    DPHook(DPDiaWebContents, @selector(pdfController), (IMP)DPWeb_pdfController);
    DPHook(DPDiaWebContents, @selector(rootFrameAccessibilityTreeId), (IMP)DPWeb_a11yRoot);
    DPHook(DPDiaWebContents, @selector(accessibilityTreeForTreeId:), (IMP)DPWeb_a11yTree);
}
