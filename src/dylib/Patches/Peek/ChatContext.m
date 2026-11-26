#import "Patches/Peek/Peek.h"
#import <objc/message.h>

static char DPPeekChatKVOContext;
static _Thread_local NSInteger DPPeekChatReading;
static _Thread_local NSInteger DPPeekChipSyncing;

typedef struct { NSInteger *depth; } DPPeekChatScope;
static void DPPeekChatLeave(DPPeekChatScope *scope) { (*scope->depth)--; }
#define DPPeekChatEnter(depth) DPPeekChatScope dp_scope __attribute__((cleanup(DPPeekChatLeave))) = { &(depth) }; (depth)++

// The composer's current-page chip is an AttachmentCellView fed by a Combine subject over the tab's cached attributes, so opening
// Peek never re-reads the tab; the cell's own rendered title/domain are the only stable handle.
static char DPPeekChipTitleKey, DPPeekChipSubtitleKey, DPPeekChipIconKey;

static id DPPeekRead(id object, SEL getter) {
    return [object respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(object, getter) : nil;
}

static Ivar DPPeekChipIvar(Class cls, const char *lazy, const char *plain) {
    return class_getInstanceVariable(cls, lazy) ?: class_getInstanceVariable(cls, plain);
}

// Swift stores these as raw Optional pointers with no ObjC type encoding, so object_getIvar: is unsafe; read the slot and bridge without retaining.
static id DPPeekChipSlot(id object, Ivar ivar) {
    if (!object || !ivar) return nil;
    void *raw = *(void **)((char *)(__bridge void *)object + ivar_getOffset(ivar));
    return (__bridge id)raw;
}

typedef struct { NSTextField *title, *subtitle; NSImageView *icon; } DPPeekChipViews;

static DPPeekChipViews DPPeekChipViewsOf(NSView *cell) {
    static Class cached;
    static Ivar title, subtitle, icon;
    if (cached != cell.class) {
        title = DPPeekChipIvar(cell.class, "$__lazy_storage_$_titleView", "titleView");
        subtitle = DPPeekChipIvar(cell.class, "$__lazy_storage_$_subtitleView", "subtitleView");
        icon = DPPeekChipIvar(cell.class, "$__lazy_storage_$_iconView", "iconView");
        cached = cell.class;
    }
    return (DPPeekChipViews){DPPeekChipSlot(cell, title), DPPeekChipSlot(cell, subtitle), DPPeekChipSlot(cell, icon)};
}

static NSString *DPPeekChipDomain(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (!host.length) return nil;
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    return host.length ? host : nil;
}

static BOOL DPPeekChipTitleMatches(NSString *shown, NSString *title) {
    if (!shown.length || !title.length) return NO;
    if ([shown isEqualToString:title]) return YES;
    NSString *trimmed = [shown stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL dots = [trimmed hasSuffix:@"..."];
    if (!dots && ![trimmed hasSuffix:@"…"]) return NO;
    NSString *prefix = [trimmed substringToIndex:trimmed.length - (dots ? 3 : 1)];
    prefix = [prefix stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return prefix.length >= 4 && [title hasPrefix:prefix];
}

// Dia's own value for a field we may have replaced, so a re-render by Dia becomes the new original instead of being matched against Peek's page.
static NSString *DPPeekChipDiaText(NSTextField *field, const void *key) {
    if (!field) return nil;
    NSArray *saved = DPGet(field, key);
    if (!saved) return field.stringValue;
    NSString *current = field.stringValue;
    return [current isEqual:saved[0]] || [current isEqual:saved[1]] ? saved[0] : current;
}

static void DPPeekChipSetText(NSTextField *field, const void *key, NSString *ours) {
    if (!field) return;
    NSString *current = field.stringValue;
    NSArray *saved = DPGet(field, key);
    NSString *dia = DPPeekChipDiaText(field, key);
    if (ours) {
        DPSet(field, key, @[ dia ?: @"", ours ]);
        if (![current isEqual:ours]) field.stringValue = ours;
    } else {
        if (saved) DPSet(field, key, nil);
        if (dia && ![current isEqual:dia]) field.stringValue = dia;
    }
}

static void DPPeekChipSetIcon(NSImageView *view, const void *key, NSImage *ours) {
    if (!view) return;
    NSImage *current = view.image;
    NSArray *saved = DPGet(view, key);
    NSImage *dia = saved ? saved[0] : current;
    if (saved && current != saved[0] && current != saved[1]) dia = current;
    if (ours && dia) {
        DPSet(view, key, @[ dia, ours ]);
        if (current != ours) view.image = ours;
    } else {
        if (saved) DPSet(view, key, nil);
        if (dia && current != dia) view.image = dia;
    }
}

// Only the current-page chip mirrors the active tab, so its rendered title and domain tell it from an @-mentioned tab, PDF or screenshot;
// once claimed, the domain alone keeps it so a re-render by Dia can't drop the chip back to the background page.
static BOOL DPPeekChipIsCurrentPage(DPPeekCard *peek, NSString *title, NSString *subtitle, BOOL claimed) {
    id source = peek.source;
    if (!source) return NO;
    NSString *tabTitle = DPPeekRead(source, @selector(title));
    NSString *tabDomain = DPPeekChipDomain(DPPeekRead(source, @selector(url)));
    BOOL domain = subtitle.length && tabDomain.length && [subtitle caseInsensitiveCompare:tabDomain] == NSOrderedSame;
    BOOL name = DPPeekChipTitleMatches(title, tabTitle);
    if (claimed) return domain || name;
    if (subtitle.length && tabDomain.length) return domain && (name || !title.length);
    return name;
}

static void DPPeekChatSyncChip(DPPeekCard *peek, NSView *cell) {
    DPPeekChipViews views = DPPeekChipViewsOf(cell);
    if (![views.title isKindOfClass:NSTextField.class] && ![views.subtitle isKindOfClass:NSTextField.class]) return;
    BOOL claimed = DPGet(views.title, &DPPeekChipTitleKey) || DPGet(views.subtitle, &DPPeekChipSubtitleKey);
    BOOL current = peek && DPPeek.on && DPPeekChipIsCurrentPage(peek, DPPeekChipDiaText(views.title, &DPPeekChipTitleKey),
                                                               DPPeekChipDiaText(views.subtitle, &DPPeekChipSubtitleKey), claimed);
    NSString *ourTitle = nil, *ourSubtitle = nil;
    NSImage *ourIcon = nil;
    if (current) {
        id page = peek.page;
        NSString *pageTitle = DPPeekRead(page, @selector(title));
        NSString *domain = DPPeekChipDomain(DPPeekRead(page, @selector(url)));
        ourTitle = pageTitle.length ? pageTitle : domain;
        ourSubtitle = domain;
        id favicon = DPPeekRead(page, @selector(favicon));
        if ([favicon isKindOfClass:NSImage.class]) ourIcon = favicon;
    }
    DPPeekChipSetText(views.title, &DPPeekChipTitleKey, ourTitle);
    DPPeekChipSetText(views.subtitle, &DPPeekChipSubtitleKey, ourSubtitle);
    DPPeekChipSetIcon(views.icon, &DPPeekChipIconKey, ourIcon);
}

// Same rule as DPPeekCardIn, kept local so this file links without Card.m in the ABI/KVO harness.
static DPPeekCard *DPPeekChipCardIn(NSWindow *window) {
    if (!window) return nil;
    for (DPPeekCard *peek in DPPeekAllCards(window))
        if (peek.window == window && !peek.closing && !peek.isHiddenOrHasHiddenAncestor) return peek;
    return nil;
}

static void DPPeekChatSyncChipsIn(NSView *view, Class cellClass, DPPeekCard *peek) {
    if (!view) return;
    if ([view isKindOfClass:cellClass]) DPPeekChatSyncChip(peek, view);
    for (NSView *child in view.subviews) DPPeekChatSyncChipsIn(child, cellClass, peek);
}

static void DPPeekChatSyncChips(NSWindow *window) {
    if (!window || DPPeekChipSyncing) return;
    Class cellClass = objc_getClass(DPDiaAttachmentCell);
    if (!cellClass) return;
    DPPeekCard *peek = DPPeek.on ? DPPeekChipCardIn(window) : nil;
    DPPeekChipSyncing++;
    DPPeekChatSyncChipsIn(window.contentView, cellClass, peek);
    DPPeekChipSyncing--;
}

static void DPPeekChatSyncAllChips(void) {
    for (NSWindow *window in NSApp.windows) DPPeekChatSyncChips(window);
}

// Dia re-renders the chip from its own state on every layout pass, so re-apply there.
static void DPPeekChip_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPeekChip_layout, self);
    if (DPPeekChipSyncing) return;
    NSWindow *window = self.window;
    if (!window) return;
    DPPeekChipSyncing++;
    DPPeekChatSyncChip(DPPeek.on ? DPPeekChipCardIn(window) : nil, self);
    DPPeekChipSyncing--;
}

// A reused cell keeps its lazily created subviews, so the saved originals would make the next row look claimed; hand it back to Dia unclaimed.
static void DPPeekChip_prepareForReuse(NSView *self, SEL _cmd) {
    DPPeekChipViews views = DPPeekChipViewsOf(self);
    DPPeekChipSyncing++;
    if ([views.title isKindOfClass:NSTextField.class]) DPPeekChipSetText(views.title, &DPPeekChipTitleKey, nil);
    if ([views.subtitle isKindOfClass:NSTextField.class]) DPPeekChipSetText(views.subtitle, &DPPeekChipSubtitleKey, nil);
    if ([views.icon isKindOfClass:NSImageView.class]) DPPeekChipSetIcon(views.icon, &DPPeekChipIconKey, nil);
    DPPeekChipSyncing--;
    DPCallOriginal(DPPeekChip_prepareForReuse, self);
}

static DPPeekCard *DPPeekChatCardFor(id webContents) {
    if (!DPPeek.on || DPPeekFindingLink || !webContents || !DPPeekHasCards()) return nil;
    for (DPPeekCard *peek in DPPeekAllCards(nil)) {
        if (peek.closing || !peek.window || peek.isHiddenOrHasHiddenAncestor) continue;
        if (peek.source == webContents && peek.page && peek.page != webContents) return peek;
    }
    return nil;
}

static id DPPeekTarget(id webContents) { return DPPeekChatCardFor(webContents).page ?: webContents; }

// Dia's page context is built inside the assistant's own extraction call, the only place a read of title/url/favicon
// can be told apart from the tab row, address bar and session store reading the same properties.
static id DPPeekContextTarget(id webContents) { return DPPeekChatReading ? DPPeekTarget(webContents) : webContents; }

// Re-runs Dia's page capture: the composer chip and prompt context subscribe to these keys, and PrefetchCacheEntry's input timestamp gates the cached scrape.
static void DPPeekNotifySource(id source, BOOL selection) {
    static NSString *const keys[] = { @"selectedText", @"title", @"url", @"favicon", @"inputEvent" };
    if (!source) return;
    for (size_t i = selection ? 0 : 1; i < sizeof keys / sizeof *keys; i++) {
        [source willChangeValueForKey:keys[i]];
        [source didChangeValueForKey:keys[i]];
    }
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
    for (NSString *key in @[ @"selectedText", @"isLoading", @"url", @"title", @"favicon" ]) {
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
    DPPeekChatSyncAllChips();
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
    DPPeekChatSyncAllChips();
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
    DPPeekChatSyncAllChips();
}

void DPPeekChatVisibilityDidChange(DPPeekCard *peek) {
    if (!DPPeek.on || !peek || peek.closing || !peek.source) return;
    DPPeekNotifySource(peek.source, YES);
    DPPeekChatSyncAllChips();
}

static void DPPageExtract_get(id self, SEL _cmd, id webContents, id completion) {
    id target = DPPeekTarget(webContents);
    id wrapped = completion;
    if (target != webContents && completion) {
        wrapped = ^(id content) {
            DPPeekChatEnter(DPPeekChatReading);
            ((void (^)(id))completion)(content);
        };
    }
    DPPeekChatEnter(DPPeekChatReading);
    DPCallOriginal(DPPageExtract_get, self, target, wrapped);
}

static void DPWeb_execReason(id self, SEL _cmd, NSString *script, NSString *reason, id completion) {
    id target = DPPeekTarget(self);
    DPCallOriginal(DPWeb_execReason, target, script, reason, completion);
}

static void DPWeb_exec(id self, SEL _cmd, NSString *script, id completion) {
    id target = DPPeekTarget(self);
    DPCallOriginal(DPWeb_exec, target, script, completion);
}

static NSString *DPWeb_selectedText(id self, SEL _cmd) {
    id target = DPPeekTarget(self);
    return DPCallOriginal(DPWeb_selectedText, target);
}

static void DPWeb_captureViewport(id self, SEL _cmd, id completion) {
    id target = DPPeekTarget(self);
    DPCallOriginal(DPWeb_captureViewport, target, completion);
}

static void DPWeb_captureFullPage(id self, SEL _cmd, id completion) {
    id target = DPPeekTarget(self);
    DPCallOriginal(DPWeb_captureFullPage, target, completion);
}

static void DPWeb_captureRegion(id self, SEL _cmd, CGRect region, id completion) {
    id target = DPPeekTarget(self);
    DPCallOriginal(DPWeb_captureRegion, target, region, completion);
}

static NSString *DPWeb_mimeType(id self, SEL _cmd) {
    id target = DPPeekTarget(self);
    return DPCallOriginal(DPWeb_mimeType, target);
}

static id DPWeb_pdfController(id self, SEL _cmd) {
    id target = DPPeekTarget(self);
    return DPCallOriginal(DPWeb_pdfController, target);
}

static NSString *DPWeb_a11yRoot(id self, SEL _cmd) {
    id target = DPPeekTarget(self);
    return DPCallOriginal(DPWeb_a11yRoot, target);
}

static id DPWeb_a11yTree(id self, SEL _cmd, NSString *treeId) {
    id target = DPPeekTarget(self);
    return DPCallOriginal(DPWeb_a11yTree, target, treeId);
}

static NSString *DPWeb_title(id self, SEL _cmd) {
    id target = DPPeekContextTarget(self);
    return DPCallOriginal(DPWeb_title, target);
}

static NSURL *DPWeb_url(id self, SEL _cmd) {
    id target = DPPeekContextTarget(self);
    return DPCallOriginal(DPWeb_url, target);
}

static id DPWeb_favicon(id self, SEL _cmd) {
    id target = DPPeekContextTarget(self);
    return DPCallOriginal(DPWeb_favicon, target);
}

// These sit on every JS, capture and title/url/favicon read in Dia, so they go in only once Peek is on.
static void DPPeekEachWebHook(void (^visit)(SEL sel, IMP imp)) {
    visit(@selector(executeJavascript:reason:completion:), (IMP)DPWeb_execReason);
    visit(@selector(executeJavascript:completion:), (IMP)DPWeb_exec);
    visit(@selector(selectedText), (IMP)DPWeb_selectedText);
    visit(@selector(captureViewport:), (IMP)DPWeb_captureViewport);
    visit(@selector(captureFullPage:), (IMP)DPWeb_captureFullPage);
    visit(@selector(captureRegion:completion:), (IMP)DPWeb_captureRegion);
    visit(@selector(contentsMimeType), (IMP)DPWeb_mimeType);
    visit(@selector(pdfController), (IMP)DPWeb_pdfController);
    visit(@selector(rootFrameAccessibilityTreeId), (IMP)DPWeb_a11yRoot);
    visit(@selector(accessibilityTreeForTreeId:), (IMP)DPWeb_a11yTree);
    visit(@selector(title), (IMP)DPWeb_title);
    visit(@selector(url), (IMP)DPWeb_url);
    visit(@selector(favicon), (IMP)DPWeb_favicon);
}

void DPPeekEnableChatContext(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ DPPeekEachWebHook(^(SEL sel, IMP imp) { DPHook(DPDiaWebContents, sel, imp); }); });
}

NSString *DPPeekChatContextProblem(void) {
    Class cls = objc_getClass(DPDiaWebContents);
    __block BOOL missing = NO;
    DPPeekEachWebHook(^(SEL sel, IMP imp) { if (class_getInstanceMethod(cls, sel) && !DPIsHooked(cls, sel, imp)) missing = YES; });
    return missing ? @"chat doesn't read the Peek page" : nil;
}

void DPPeekInstallChatContext(void) {
    DPHook(DPDiaAttachmentCell, @selector(layout), (IMP)DPPeekChip_layout);
    DPHook(DPDiaAttachmentCell, @selector(prepareForReuse), (IMP)DPPeekChip_prepareForReuse);
    DPHook(DPDiaPageContentExtraction, @selector(getExtractedContentForWebContents:completion:), (IMP)DPPageExtract_get);
    if (DPPeek.on) DPPeekEnableChatContext();
}
