#import "Patches/Peek/Peek.h"
#import <Carbon/Carbon.h>
#import <objc/runtime.h>

static int gChatMenuTriggers, gNewChatTriggers, gExtMenuTriggers, gChatButtonClicks;

@interface ArcWebContents : NSObject <DPPeekPage>
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) id favicon;
@property (nonatomic, copy) NSString *selectedText;
@property (nonatomic, copy) NSString *inputEvent;
@property (nonatomic, copy) NSString *contentsMimeType;
@property (nonatomic, strong) id pdfController;
@property (nonatomic, copy) NSString *rootFrameAccessibilityTreeId;
@property (nonatomic) BOOL isLoading, isReadyToDisplay;
@property (nonatomic, strong) NSView *attachedHost;
- (void)executeJavascript:(NSString *)script reason:(NSString *)reason completion:(void (^)(NSString *result, BOOL ok))completion;
- (void)executeJavascript:(NSString *)script completion:(void (^)(NSString *result, BOOL ok))completion;
- (void)captureViewport:(void (^)(NSString *tag))completion;
- (void)captureFullPage:(void (^)(NSString *tag))completion;
- (void)captureRegion:(CGRect)region completion:(void (^)(NSString *tag, CGRect rect))completion;
- (id)accessibilityTreeForTreeId:(NSString *)treeId;
@end

@implementation ArcWebContents
- (NSView *)createPaneHostView { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)]; }
- (void)attachToPaneHostView:(NSView *)host { self.attachedHost = host; }
- (void)detachFromPaneHostView:(NSView *)host { if (self.attachedHost == host) self.attachedHost = nil; }
- (void)close {}
- (id)navigationController { return self; }
- (id)load:(NSURL *)url initiatorOrigin:(NSURL *)origin { self.url = url; return nil; }
- (void)executeJavascript:(NSString *)script reason:(NSString *)reason completion:(void (^)(NSString *, BOOL))completion {
    if (completion) completion([NSString stringWithFormat:@"%@:%@:%@", self.tag, reason ?: @"", script ?: @""], YES);
}
- (void)executeJavascript:(NSString *)script completion:(void (^)(NSString *, BOOL))completion {
    if (completion) completion([NSString stringWithFormat:@"%@:%@", self.tag, script ?: @""], YES);
}
- (void)captureViewport:(void (^)(NSString *))completion { if (completion) completion(self.tag); }
- (void)captureFullPage:(void (^)(NSString *))completion { if (completion) completion(self.tag); }
- (void)captureRegion:(CGRect)region completion:(void (^)(NSString *, CGRect))completion { if (completion) completion(self.tag, region); }
- (id)accessibilityTreeForTreeId:(NSString *)treeId { return [NSString stringWithFormat:@"%@:%@", self.tag, treeId]; }
@end

static ArcWebContents *gExtractProbe;
static BOOL gExtractAsync;
static NSString *gProbeTitle, *gProbeURL;
static id gProbeFavicon;

@interface ArcBrowserContextPageContentExtraction : NSObject
- (void)getExtractedContentForWebContents:(ArcWebContents *)webContents completion:(void (^)(NSDictionary *content))completion;
@end

@implementation ArcBrowserContextPageContentExtraction
- (void)getExtractedContentForWebContents:(ArcWebContents *)webContents completion:(void (^)(NSDictionary *))completion {
    if (gExtractProbe) {
        gProbeTitle = gExtractProbe.title;
        gProbeURL = gExtractProbe.url.absoluteString;
        gProbeFavicon = gExtractProbe.favicon;
    }
    NSDictionary *content = @{@"tag": webContents.tag ?: @"", @"url": webContents.url.absoluteString ?: @""};
    if (gExtractAsync) dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(content); });
    else if (completion) completion(content);
}
@end

@interface ArcWebContentsConfiguration : NSObject
@end
@implementation ArcWebContentsConfiguration
@end

@interface ArcBrowserContext : NSObject
- (id)createWebContents:(id)config;
@end
@implementation ArcBrowserContext
- (id)createWebContents:(id)config {
    ArcWebContents *page = [ArcWebContents new];
    page.tag = @"peek";
    page.url = [NSURL URLWithString:@"https://peek.example/article"];
    page.title = @"Peek Article";
    page.selectedText = @"peek-selection";
    page.contentsMimeType = @"text/html";
    page.pdfController = @"peek-pdf";
    page.rootFrameAccessibilityTreeId = @"peek-root";
    page.isReadyToDisplay = YES;
    return page;
}
@end

@interface ArcBrowser : ArcBrowserContext
@end
@implementation ArcBrowser
@end

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC13NavigationBar26NavigationBarCapsuleButton : NSButton
@end
@implementation _TtC13NavigationBar26NavigationBarCapsuleButton
@end

@interface _TtC16PinnedExtensions19PinnedExtensionView : NSView
@end
@implementation _TtC16PinnedExtensions19PinnedExtensionView
@end

@interface _TtC6WindowP33_TESTAssistantSidebarContentContainerView : NSView
@end
@implementation _TtC6WindowP33_TESTAssistantSidebarContentContainerView
@end

@interface _TtC6Window33AssistantSidebarDraggerHandleView : NSView
@end
@implementation _TtC6Window33AssistantSidebarDraggerHandleView
@end

@interface _TtC20AssistantPanelUIBase22AssistantPanelRootView : NSView
@end
@implementation _TtC20AssistantPanelUIBase22AssistantPanelRootView
@end

@interface _TtC14AssistantPanel24AssistantPanelHeaderView : NSView
@end
@implementation _TtC14AssistantPanel24AssistantPanelHeaderView
@end

@interface _TtC18ExtensionSidePanel32ExtensionSidePanelViewController : NSView
@end
@implementation _TtC18ExtensionSidePanel32ExtensionSidePanelViewController
@end

@interface _TtC18ExtensionSidePanel35ExtensionSidePanelSubViewController : NSViewController
@end
@implementation _TtC18ExtensionSidePanel35ExtensionSidePanelSubViewController
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)]; }
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

@interface _TtC6Window30AssistantSidebarViewController : NSViewController
@end
@implementation _TtC6Window30AssistantSidebarViewController
- (void)viewWillLayout {}
@end

@interface _TtC6Window33AssistantSidebarLayoutCoordinator : NSObject
- (void)containerViewResized:(NSNotification *)note;
@end
@implementation _TtC6Window33AssistantSidebarLayoutCoordinator
- (void)containerViewResized:(NSNotification *)note {}
@end

@interface DPChatTestWindow : NSWindow
@property (nonatomic, weak) NSResponder *mockResponder;
@end
@implementation DPChatTestWindow
- (NSResponder *)firstResponder { return self.mockResponder ?: [super firstResponder]; }
- (BOOL)makeFirstResponder:(NSResponder *)responder { self.mockResponder = responder; return YES; }
- (BOOL)isVisible { return YES; }
@end

@interface DPMenuTarget : NSObject
@end
@implementation DPMenuTarget
- (void)toggleChat:(id)sender { gChatMenuTriggers++; }
- (void)newChat:(id)sender { gNewChatTriggers++; }
- (void)extAction:(id)sender { gExtMenuTriggers++; }
- (void)didClickAskButton:(id)sender { gChatButtonClicks++; }
@end

@interface DPKVOCounter : NSObject
@property (nonatomic) int selectedHits, inputHits;
@property (nonatomic, copy) NSString *lastSeenSelected;
@end
@implementation DPKVOCounter
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"selectedText"]) {
        self.selectedHits++;
        self.lastSeenSelected = [(ArcWebContents *)object selectedText];
    } else if ([keyPath isEqualToString:@"inputEvent"]) {
        self.inputHits++;
    }
}
@end

@interface DPTitleReader : NSObject
@property (nonatomic) int titleHits, urlHits, faviconHits;
@property (nonatomic, copy) NSString *seenTitle, *seenURL;
@property (nonatomic, strong) id seenFavicon;
@end
@implementation DPTitleReader
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    ArcWebContents *page = object;
    if ([keyPath isEqualToString:@"title"]) { self.titleHits++; self.seenTitle = page.title; }
    else if ([keyPath isEqualToString:@"url"]) { self.urlHits++; self.seenURL = page.url.absoluteString; }
    else if ([keyPath isEqualToString:@"favicon"]) { self.faviconHits++; self.seenFavicon = page.favicon; }
}
@end

DPPatch DPPeek = { .on = YES }, DPPeekPinnedLinks = { .on = YES };

static ArcBrowser *gBrowser;
id DPBrowserOfWindow(NSWindow *window) { return gBrowser; }
double DPPeekDarkness(void) { return 0.45; }
double DPPeekResponse(void) { return 0.05; }
BOOL DPPeekGenie(void) { return NO; }
BOOL DPPeekShowsToolbar(void) { return NO; }
NSView *DPPeekControls(id target, SEL action) { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 28, 100)]; }
void DPPeekAddToolbar(DPPeekCard *peek) {}
CGFloat DPPeekToolbarInset(DPPeekCard *peek) { return 0; }
void DPPeekPlaceToolbar(DPPeekCard *peek) {}
void DPPeekNavigate(id page, DPPeekStep step) {}
void DPPeekEditToolbarAddress(DPPeekCard *peek) {}
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event) { return NO; }
BOOL DPPeekZoomShortcut(DPPeekCard *peek, NSEvent *event) { return NO; }
BOOL DPPeekFindShortcut(DPPeekCard *peek, NSEvent *event, NSEventModifierFlags mods) { return NO; }
BOOL DPPeekHideFind(DPPeekCard *peek) { return NO; }
void DPPeekLayoutHints(NSView *controls, CGFloat availableRight) {}
void DPPeekResetControlHints(NSView *controls) {}
void DPPeekHideDragZone(void) {}
CATransform3D DPPeekScaled(NSView *view, CGFloat scale) { return CATransform3DIdentity; }
static NSString *gActiveTabID = @"tab-1";
id DPScriptWindow(NSWindow *window) { return nil; }
NSString *DPTabID(id tab) { return nil; }
NSString *DPActiveTabIDIn(id scriptWindow) { return gActiveTabID; }
NSString *DPActiveTabID(NSWindow *window) { return gActiveTabID; }
void DPOnLaunch(void (^block)(void)) { block(); }

BOOL DPEventIsKey(NSEvent *event, NSString *key) {
    return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:key.lowercaseString];
}

BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item) {
    if (!item.keyEquivalent.length) return NO;
    NSEventModifierFlags mask = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
    return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:item.keyEquivalent.lowercaseString] &&
           (event.modifierFlags & mask) == (item.keyEquivalentModifierMask & mask);
}

#import "Patches/Peek/Tab.m"
#import "Patches/Peek/Selection.m"
#import "Patches/Peek/Motion.m"
#import "Patches/Peek/Keys.m"
#import "Patches/Peek/Visibility.m"
#import "Patches/Peek/Chat.m"
// Dia's composer chip is an AppKit AttachmentCellView whose title/subtitle/icon live in lazily
// created subviews; the patch reaches them by ivar name, so the mock mirrors those names.
@interface _TtC11Attachments18AttachmentCellView : NSView {
@public
    id viewModel;
    NSImageView *$__lazy_storage_$_iconView;
    NSTextField *$__lazy_storage_$_titleView;
    NSTextField *$__lazy_storage_$_subtitleView;
}
@end
@implementation _TtC11Attachments18AttachmentCellView
- (void)prepareForReuse {}
@end

#import "Patches/Peek/ChatContext.m"
#import "Patches/Peek/Card.m"
#import "Patches/Peek/Pages.m"
#import "Patches/Peek/Handoff.m"

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

@interface DPCommandBarOverlay : NSView
@end
@implementation DPCommandBarOverlay
@end

static NSEvent *MakeKeyEvent(NSWindow *window, NSString *chars, unsigned short code, NSEventModifierFlags mods) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0
                        windowNumber:window.windowNumber context:nil characters:chars charactersIgnoringModifiers:chars
                           isARepeat:NO keyCode:code];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gBrowser = [ArcBrowser new];
        DPPeekInstallPages();
        DPPeekInstallChat();

        DPMenuTarget *menuTarget = [DPMenuTarget new];
        NSMenu *mainMenu = [NSMenu new];
        NSMenuItem *appRoot = [[NSMenuItem alloc] initWithTitle:@"Dia" action:nil keyEquivalent:@""];
        appRoot.submenu = [[NSMenu alloc] initWithTitle:@"Dia"];
        [mainMenu addItem:appRoot];

        NSMenuItem *chatRoot = [[NSMenuItem alloc] initWithTitle:@"Chat" action:nil keyEquivalent:@""];
        NSMenu *chatMenu = [[NSMenu alloc] initWithTitle:@"Chat"];
        NSMenuItem *toggleChatItem = [[NSMenuItem alloc] initWithTitle:@"Chat…" action:@selector(toggleChat:) keyEquivalent:@"e"];
        toggleChatItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        toggleChatItem.target = menuTarget;
        NSMenuItem *newChatItem = [[NSMenuItem alloc] initWithTitle:@"New Chat" action:@selector(newChat:) keyEquivalent:@"k"];
        newChatItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
        newChatItem.target = menuTarget;
        [chatMenu addItem:toggleChatItem];
        [chatMenu addItem:newChatItem];
        chatRoot.submenu = chatMenu;
        [mainMenu addItem:chatRoot];

        NSMenuItem *extRoot = [[NSMenuItem alloc] initWithTitle:@"Extensions" action:nil keyEquivalent:@""];
        NSMenu *extMenu = [[NSMenu alloc] initWithTitle:@"Extensions"];
        NSMenuItem *extItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Side Panel" action:@selector(extAction:) keyEquivalent:@"p"];
        extItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
        extItem.target = menuTarget;
        [extMenu addItem:extItem];
        extRoot.submenu = extMenu;
        [mainMenu addItem:extRoot];
        NSApp.mainMenu = mainMenu;

        DPChatTestWindow *window = [[DPChatTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 1200, 800)
                                                                       styleMask:NSWindowStyleMaskTitled
                                                                         backing:NSBackingStoreBuffered defer:NO];
        NSView *outerRounded = [[NSView alloc] initWithFrame:window.contentView.bounds];
        outerRounded.wantsLayer = YES;
        outerRounded.layer.cornerRadius = 10;
        outerRounded.layer.masksToBounds = YES;
        [window.contentView addSubview:outerRounded];

        NSView *sidebarRoot = [[NSView alloc] initWithFrame:outerRounded.bounds];
        [outerRounded addSubview:sidebarRoot];

        _TtC6WindowP33_TESTAssistantSidebarContentContainerView *contentContainer =
            [[_TtC6WindowP33_TESTAssistantSidebarContentContainerView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 800)];
        [sidebarRoot addSubview:contentContainer];

        NSView *pageContainer = [[NSView alloc] initWithFrame:contentContainer.bounds];
        pageContainer.wantsLayer = YES;
        [contentContainer addSubview:pageContainer];

        NSView *splitHost = [[NSView alloc] initWithFrame:pageContainer.bounds];
        [pageContainer addSubview:splitHost];

        _TtC11ContentPane15ContentPaneView *pane = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:splitHost.bounds];
        [splitHost addSubview:pane];

        // NavigationBarView at top of unflipped pane (y = 760..800), with Chat button + Pinned Extension on right.
        _TtC13NavigationBar17NavigationBarView *toolbar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 760, 1200, 40)];
        toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [pane addSubview:toolbar];

        _TtC13NavigationBar26NavigationBarCapsuleButton *chatBtn =
            [[_TtC13NavigationBar26NavigationBarCapsuleButton alloc] initWithFrame:NSMakeRect(1130, 6, 60, 28)];
        chatBtn.title = @"Chat";
        chatBtn.target = menuTarget;
        chatBtn.action = @selector(didClickAskButton:);
        chatBtn.autoresizingMask = NSViewMinXMargin;
        [toolbar addSubview:chatBtn];

        _TtC16PinnedExtensions19PinnedExtensionView *extBtn =
            [[_TtC16PinnedExtensions19PinnedExtensionView alloc] initWithFrame:NSMakeRect(1096, 6, 28, 28)];
        extBtn.autoresizingMask = NSViewMinXMargin;
        [toolbar addSubview:extBtn];

        _TtC6Window33AssistantSidebarDraggerHandleView *divider =
            [[_TtC6Window33AssistantSidebarDraggerHandleView alloc] initWithFrame:NSMakeRect(1200, 0, 0, 800)];
        [sidebarRoot addSubview:divider];

        _TtC20AssistantPanelUIBase22AssistantPanelRootView *chatPanel =
            [[_TtC20AssistantPanelUIBase22AssistantPanelRootView alloc] initWithFrame:NSMakeRect(1200, 0, 0, 800)];
        NSView *chatInput = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 200, 40)];
        [chatPanel addSubview:chatInput];
        [sidebarRoot addSubview:chatPanel];

        _TtC18ExtensionSidePanel32ExtensionSidePanelViewController *extPanel =
            [[_TtC18ExtensionSidePanel32ExtensionSidePanelViewController alloc] initWithFrame:NSMakeRect(1200, 0, 0, 800)];
        NSView *extInput = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 200, 40)];
        [extPanel addSubview:extInput];
        [sidebarRoot addSubview:extPanel];

        _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView *floatingChat =
            [[_TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView alloc] initWithFrame:NSMakeRect(200, 100, 320, 400)];
        _TtC14AssistantPanel24AssistantPanelHeaderView *floatingHeader =
            [[_TtC14AssistantPanel24AssistantPanelHeaderView alloc] initWithFrame:NSMakeRect(0, 360, 320, 40)];
        NSView *floatingInput = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 200, 40)];
        [floatingChat addSubview:floatingHeader];
        [floatingChat addSubview:floatingInput];
        [sidebarRoot addSubview:floatingChat];

        _TtC6Window30AssistantSidebarViewController *sidebarVC = [_TtC6Window30AssistantSidebarViewController new];
        sidebarVC.view = sidebarRoot;
        _TtC6Window33AssistantSidebarLayoutCoordinator *layoutCoord = [_TtC6Window33AssistantSidebarLayoutCoordinator new];

        ArcWebContents *source = [ArcWebContents new];
        source.tag = @"parent";
        source.url = [NSURL URLWithString:@"https://parent.example/list"];
        source.title = @"Parent Page";
        source.selectedText = @"parent-selection";
        source.contentsMimeType = @"application/pdf";
        source.pdfController = @"parent-pdf";
        source.rootFrameAccessibilityTreeId = @"parent-root";

        ArcWebContents *other = [ArcWebContents new];
        other.tag = @"other";
        other.url = [NSURL URLWithString:@"https://other.example/"];
        other.selectedText = @"other-selection";

        DPKVOCounter *kvo = [DPKVOCounter new];
        [source addObserver:kvo forKeyPath:@"selectedText" options:0 context:NULL];
        [source addObserver:kvo forKeyPath:@"inputEvent" options:0 context:NULL];

        DPPeekOpenFrom(window, @"tab-1", [NSURL URLWithString:@"https://peek.example/article"], NSMakeRect(100, 100, 40, 20), nil, source, nil, nil);
        DPPeekCard *peek = DPPeekCardIn(window);
        ArcWebContents *peekPage = (ArcWebContents *)peek.page;
        CHECK(peek != nil && peekPage != nil, "Peek card opened");

        CHECK(peek.superview == pageContainer, "DPPeekCard mounts inside AssistantSidebarContentContainerView's page container");
        CHECK(kvo.selectedHits == 1 && kvo.inputHits == 1, "attaching Peek notifies source selectedText and inputEvent KVO");
        CHECK([kvo.lastSeenSelected isEqualToString:@"peek-selection"], "source selectedText reads Peek selection on attach");

        [peek layoutSubtreeIfNeeded];
        NSPoint chatBtnInWindow = [window.contentView convertPoint:NSMakePoint(NSMidX(chatBtn.bounds), NSMidY(chatBtn.bounds)) fromView:chatBtn];
        NSPoint extBtnInWindow = [window.contentView convertPoint:NSMakePoint(NSMidX(extBtn.bounds), NSMidY(extBtn.bounds)) fromView:extBtn];
        NSPoint backdropInWindow = [window.contentView convertPoint:NSMakePoint(20, 20) fromView:pane];
        NSView *hitChat = [window.contentView hitTest:chatBtnInWindow];
        NSView *hitExt = [window.contentView hitTest:extBtnInWindow];
        NSView *hitBackdrop = [window.contentView hitTest:backdropInWindow];
        CHECK(hitChat == chatBtn || [hitChat isDescendantOf:chatBtn], "clicking toolbar Chat button passes through Peek backdrop");
        CHECK(hitExt == extBtn || [hitExt isDescendantOf:extBtn], "clicking pinned extension button passes through Peek backdrop");
        CHECK(hitBackdrop == peek || [hitBackdrop isDescendantOf:peek], "clicking backdrop outside chat controls still hits Peek");

        chatBtn.hidden = YES;
        NSView *hitHiddenChat = [window.contentView hitTest:chatBtnInWindow];
        CHECK(hitHiddenChat == peek || [hitHiddenChat isDescendantOf:peek], "hidden Chat button does not pass through Peek backdrop");
        chatBtn.hidden = NO;

        contentContainer.frame = NSMakeRect(0, 0, 820, 800);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane.frame = splitHost.bounds;
        toolbar.frame = NSMakeRect(0, 760, 820, 40);
        chatBtn.frame = NSMakeRect(732, 6, 78, 28);
        extBtn.frame = NSMakeRect(692, 6, 28, 28);
        divider.frame = NSMakeRect(820, 0, 8, 800);
        chatPanel.frame = NSMakeRect(828, 0, 372, 800);
        [sidebarVC viewWillLayout];
        [peek layoutSubtreeIfNeeded];

        CHECK(NSEqualRects(peek.frame, NSMakeRect(0, 0, 820, 800)), "Peek card shrinks to page pane width when docked AI Side Chat opens");
        NSRect coverInWindow = [peek convertRect:peek.bounds toView:nil];
        NSRect chatInWindow = [chatPanel convertRect:chatPanel.bounds toView:nil];
        CHECK(NSMaxX(coverInWindow) <= NSMinX(chatInWindow), "handoff cover bounds stop at the page pane and never cover AI Side Chat");
        NSRect chatInPeek = [peek convertRect:chatBtn.bounds fromView:chatBtn];
        CHECK(!NSIntersectsRect(peek.controls.frame, chatInPeek), "Peek controls shift clear of visible toolbar Chat button");

        NSPoint inDivider = [window.contentView convertPoint:NSMakePoint(4, 400) fromView:divider];
        NSPoint inChatPanel = [window.contentView convertPoint:NSMakePoint(100, 400) fromView:chatPanel];
        NSPoint inFloating = [window.contentView convertPoint:NSMakePoint(100, 100) fromView:floatingChat];
        CHECK([window.contentView hitTest:inDivider] == divider, "divider drag hits AssistantSidebarDraggerHandleView, keeping Peek open");
        CHECK([[window.contentView hitTest:inChatPanel] isDescendantOf:chatPanel], "clicks inside docked AI Side Chat never hit Peek");
        CHECK([[window.contentView hitTest:inFloating] isDescendantOf:floatingChat], "clicks inside floating chat popover never hit Peek");

        contentContainer.frame = NSMakeRect(0, 0, 420, 800);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane.frame = splitHost.bounds;
        toolbar.frame = NSMakeRect(0, 760, 420, 40);
        chatBtn.frame = NSMakeRect(334, 6, 78, 28);
        divider.frame = NSMakeRect(420, 0, 8, 800);
        chatPanel.frame = NSMakeRect(428, 0, 772, 800);
        [layoutCoord containerViewResized:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:sidebarRoot]];
        [peek layoutSubtreeIfNeeded];
        CHECK(fabs(NSWidth(peek.frame) - 420) < 0.5, "Peek follows narrow pane resize via layout coordinator");
        CHECK(NSMaxX(peek.controls.frame) <= NSWidth(peek.bounds), "Peek controls stay inside narrow page pane beside wide chat");

        contentContainer.frame = NSMakeRect(0, 0, 1200, 756);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane.frame = splitHost.bounds;
        toolbar.frame = NSMakeRect(0, 716, 1200, 40);
        chatBtn.frame = NSMakeRect(1110, 6, 78, 28);
        divider.frame = NSMakeRect(1200, 0, 0, 756);
        chatPanel.frame = NSMakeRect(1200, 0, 0, 756);
        [sidebarVC viewWillLayout];
        [peek layoutSubtreeIfNeeded];
        CHECK(NSEqualRects(peek.frame, NSMakeRect(0, 0, 1200, 756)), "Peek expands cleanly when chat closes in Top-Tab layout");

        window.mockResponder = peek.host;
        gChatMenuTriggers = gNewChatTriggers = gExtMenuTriggers = gChatButtonClicks = 0;
        NSEvent *cmdE = MakeKeyEvent(window, @"e", kVK_ANSI_E, NSEventModifierFlagCommand);
        CHECK(DPPeekChatShortcut(peek, cmdE, NSEventModifierFlagCommand), "Cmd+E handled while Peek focused");
        CHECK(gChatMenuTriggers == 1 && !peek.closing, "Cmd+E invokes Chat menu item and keeps Peek open");

        NSEvent *cmdShiftK = MakeKeyEvent(window, @"k", kVK_ANSI_K, NSEventModifierFlagCommand | NSEventModifierFlagShift);
        CHECK(DPPeekChatShortcut(peek, cmdShiftK, NSEventModifierFlagCommand | NSEventModifierFlagShift), "remapped New Chat shortcut handled");
        CHECK(gNewChatTriggers == 1 && !peek.closing, "New Chat shortcut keeps Peek open");

        NSEvent *cmdOptP = MakeKeyEvent(window, @"p", kVK_ANSI_P, NSEventModifierFlagCommand | NSEventModifierFlagOption);
        CHECK(DPPeekChatShortcut(peek, cmdOptP, NSEventModifierFlagCommand | NSEventModifierFlagOption), "Extensions menu shortcut handled");
        CHECK(gExtMenuTriggers == 1 && !peek.closing, "Extensions shortcut keeps Peek open");

        toggleChatItem.hidden = YES;
        CHECK(!DPPeekChatShortcut(peek, cmdE, NSEventModifierFlagCommand), "hidden Chat menu item (TurnOffAI) is not triggered");
        CHECK(gChatMenuTriggers == 1 && gChatButtonClicks == 0, "TurnOffAI hidden item does not bypass to Chat button");
        toggleChatItem.hidden = NO;

        toggleChatItem.keyEquivalent = @"";
        CHECK(DPPeekChatShortcut(peek, cmdE, NSEventModifierFlagCommand), "Cmd+E falls back to visible Chat button when menu has no binding");
        CHECK(gChatButtonClicks == 1 && !peek.closing, "fallback Chat button click fires and keeps Peek open");
        toggleChatItem.keyEquivalent = @"e";

        _TtC18ExtensionSidePanel35ExtensionSidePanelSubViewController *extVC = [_TtC18ExtensionSidePanel35ExtensionSidePanelSubViewController new];
        NSView *extVCChild = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)];
        [extVC.view addSubview:extVCChild];
        [sidebarRoot addSubview:extVC.view];
        CHECK(!DPPeekResponderInChat(peek.host), "Peek host is not detected as chat responder");
        CHECK(DPPeekResponderInChat(chatInput), "docked AI Side Chat input detected as chat responder");
        CHECK(DPPeekResponderInChat(floatingInput), "floating chat popover input detected as chat responder");
        CHECK(DPPeekResponderInChat(extInput), "Extension Side Panel input detected as chat responder");
        CHECK(DPPeekResponderInChat(extVCChild), "Extension Side Panel NSViewController nextResponder detected as chat responder");
        [extVC.view removeFromSuperview];

        window.mockResponder = peek.host;
        NSEvent *cmdW = MakeKeyEvent(window, @"w", kVK_ANSI_W, NSEventModifierFlagCommand);
        NSEvent *esc = MakeKeyEvent(window, @"\x1b", kVK_Escape, 0);
        DPCommandBarOverlay *cmdOverlay = [[DPCommandBarOverlay alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:cmdOverlay];
        CHECK(DPPeekHandleKeyEvent(peek, cmdW) == cmdW && !peek.closing, "visible DPCommandBarOverlay passes Cmd+W through without closing Peek");
        CHECK(DPPeekHandleKeyEvent(peek, esc) == esc && !peek.closing, "visible DPCommandBarOverlay passes Escape through without closing Peek");
        cmdOverlay.hidden = YES;
        NSTextView *sidebarRename = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 120, 20)];
        [sidebarRoot addSubview:sidebarRename];
        window.mockResponder = sidebarRename;
        CHECK(DPPeekHandleKeyEvent(peek, cmdW) == cmdW && !peek.closing, "external NSText focus passes Cmd+W through without closing Peek");
        [sidebarRename removeFromSuperview];
        [cmdOverlay removeFromSuperview];
        window.mockResponder = peek.host;

        ArcBrowserContextPageContentExtraction *extractor = [ArcBrowserContextPageContentExtraction new];
        __block NSDictionary *extracted = nil;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"peek"] && [extracted[@"url"] isEqualToString:@"https://peek.example/article"],
              "page content extraction routes from parent tab to visible Peek page");

        __block NSString *jsReason = nil, *jsPlain = nil, *vpTag = nil, *fpTag = nil, *regTag = nil;
        __block CGRect regGot = CGRectZero;
        [source executeJavascript:@"outerHTML" reason:@"chat" completion:^(NSString *r, BOOL ok) { jsReason = r; }];
        [source executeJavascript:@"title" completion:^(NSString *r, BOOL ok) { jsPlain = r; }];
        [source captureViewport:^(NSString *t) { vpTag = t; }];
        [source captureFullPage:^(NSString *t) { fpTag = t; }];
        [source captureRegion:CGRectMake(1, 2, 30, 40) completion:^(NSString *t, CGRect r) { regTag = t; regGot = r; }];
        CHECK([jsReason isEqualToString:@"peek:chat:outerHTML"], "executeJavascript:reason:completion: routes to Peek");
        CHECK([jsPlain isEqualToString:@"peek:title"], "executeJavascript:completion: routes to Peek");
        CHECK([source.selectedText isEqualToString:@"peek-selection"], "selectedText routes to Peek");
        CHECK([vpTag isEqualToString:@"peek"] && [fpTag isEqualToString:@"peek"], "viewport and full-page capture route to Peek");
        CHECK([regTag isEqualToString:@"peek"] && CGRectEqualToRect(regGot, CGRectMake(1, 2, 30, 40)), "captureRegion routes to Peek with intact rect");
        CHECK([source.contentsMimeType isEqualToString:@"text/html"], "contentsMimeType routes to Peek");
        CHECK([source.pdfController isEqual:@"peek-pdf"], "pdfController routes to Peek");
        CHECK([source.rootFrameAccessibilityTreeId isEqualToString:@"peek-root"], "rootFrameAccessibilityTreeId routes to Peek");
        CHECK([[source accessibilityTreeForTreeId:@"t1"] isEqualToString:@"peek:t1"], "accessibilityTreeForTreeId: routes to Peek");

        DPPeekFindingLink = YES;
        __block NSString *linkJS = nil;
        [source executeJavascript:@"link" completion:^(NSString *r, BOOL ok) { linkJS = r; }];
        DPPeekFindingLink = NO;
        CHECK([linkJS isEqualToString:@"parent:link"], "DPPeekFindingLink keeps link lookup on parent page");

        extracted = nil;
        [extractor getExtractedContentForWebContents:other completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"other"] && [other.selectedText isEqualToString:@"other-selection"],
              "other tabs remain completely untouched");

        peekPage.favicon = @"peek-icon";
        DPTitleReader *reader = [DPTitleReader new];
        for (NSString *key in @[ @"title", @"url", @"favicon" ]) [source addObserver:reader forKeyPath:key options:0 context:NULL];
        source.title = @"Parent Page";
        source.url = [NSURL URLWithString:@"https://parent.example/list"];
        source.favicon = @"parent-icon";
        CHECK([reader.seenTitle isEqualToString:@"Parent Page"] && [reader.seenURL isEqualToString:@"https://parent.example/list"] &&
              [reader.seenFavicon isEqual:@"parent-icon"], "KVO observers see the real parent tab title, URL and favicon");

        CHECK([source.title isEqualToString:@"Parent Page"], "the tab row and address bar still read the parent tab title");
        CHECK([source.url.absoluteString isEqualToString:@"https://parent.example/list"], "the tab row and address bar still read the parent tab URL");
        CHECK([source.favicon isEqual:@"parent-icon"], "the tab row still reads the parent tab favicon");
        CHECK(other.title == nil && other.favicon == nil, "other tabs keep their own title and favicon");

        gExtractProbe = source;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) {}];
        CHECK([gProbeTitle isEqualToString:@"Peek Article"], "the assistant's capture reads the Peek title off the tab it holds");
        CHECK([gProbeURL isEqualToString:@"https://peek.example/article"], "the assistant's capture reads the Peek URL off the tab it holds");
        CHECK([gProbeFavicon isEqual:@"peek-icon"], "the assistant's capture reads the Peek favicon off the tab it holds");

        __block NSString *inCompletion = nil;
        gExtractAsync = YES;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { inCompletion = source.title; }];
        gExtractAsync = NO;
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK([inCompletion isEqualToString:@"Peek Article"], "the capture completion also reads the Peek page");
        gExtractProbe = nil;

        int titleHits = reader.titleHits, urlHits = reader.urlHits, iconHits = reader.faviconHits;
        peekPage.title = @"Peek Article Two";
        CHECK(reader.titleHits > titleHits && reader.urlHits > urlHits && reader.faviconHits > iconHits,
              "a Peek title change re-notifies the tab's title, URL and favicon KVO");
        titleHits = reader.titleHits; urlHits = reader.urlHits; iconHits = reader.faviconHits;
        peekPage.favicon = @"peek-icon-two";
        CHECK(reader.titleHits > titleHits && reader.urlHits > urlHits && reader.faviconHits > iconHits,
              "a Peek favicon change re-notifies the tab's title, URL and favicon KVO");
        titleHits = reader.titleHits; urlHits = reader.urlHits; iconHits = reader.faviconHits;
        peekPage.url = [NSURL URLWithString:@"https://peek.example/second"];
        CHECK(reader.titleHits > titleHits && reader.urlHits > urlHits && reader.faviconHits > iconHits,
              "a Peek URL change re-notifies the tab's title, URL and favicon KVO");
        CHECK([reader.seenTitle isEqualToString:@"Parent Page"], "KVO observers still see the real parent tab title");
        CHECK([reader.seenURL isEqualToString:@"https://parent.example/list"], "KVO observers still see the real parent tab URL");
        CHECK([reader.seenFavicon isEqual:@"parent-icon"], "KVO observers still see the real parent tab favicon");

        Ivar storedTitle = class_getInstanceVariable(ArcWebContents.class, "_title");
        Ivar storedURL = class_getInstanceVariable(ArcWebContents.class, "_url");
        CHECK([object_getIvar(source, storedTitle) isEqualToString:@"Parent Page"], "the parent tab's stored title is never overwritten by Peek");
        CHECK([[(NSURL *)object_getIvar(source, storedURL) absoluteString] isEqualToString:@"https://parent.example/list"],
              "the parent tab's stored URL is never overwritten by Peek");

        for (NSString *key in @[ @"title", @"url", @"favicon" ]) [source removeObserver:reader forKeyPath:key];

        _TtC11Attachments18AttachmentCellView *chip = [[_TtC11Attachments18AttachmentCellView alloc] initWithFrame:NSMakeRect(0, 0, 184, 54)];
        chip->$__lazy_storage_$_titleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 16)];
        chip->$__lazy_storage_$_subtitleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 14)];
        chip->$__lazy_storage_$_iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        for (NSView *part in @[ chip->$__lazy_storage_$_titleView, chip->$__lazy_storage_$_subtitleView, chip->$__lazy_storage_$_iconView ])
            [chip addSubview:part];
        chip->$__lazy_storage_$_titleView.stringValue = @"Parent Page";
        chip->$__lazy_storage_$_subtitleView.stringValue = @"parent.example";
        NSImage *parentIcon = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        chip->$__lazy_storage_$_iconView.image = parentIcon;
        [window.contentView addSubview:chip];

        _TtC11Attachments18AttachmentCellView *otherChip = [[_TtC11Attachments18AttachmentCellView alloc] initWithFrame:NSMakeRect(0, 60, 184, 54)];
        otherChip->$__lazy_storage_$_titleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 16)];
        otherChip->$__lazy_storage_$_subtitleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 14)];
        otherChip->$__lazy_storage_$_iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        for (NSView *part in @[ otherChip->$__lazy_storage_$_titleView, otherChip->$__lazy_storage_$_subtitleView, otherChip->$__lazy_storage_$_iconView ])
            [otherChip addSubview:part];
        otherChip->$__lazy_storage_$_titleView.stringValue = @"Other Page";
        otherChip->$__lazy_storage_$_subtitleView.stringValue = @"other.example";
        NSImage *otherIcon = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        otherChip->$__lazy_storage_$_iconView.image = otherIcon;
        [window.contentView addSubview:otherChip];

        [chip layout];
        [otherChip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Peek Article Two"],
              "the current-page chip takes the Peek page title");
        CHECK([chip->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"peek.example"],
              "the current-page chip takes the Peek page domain");
        CHECK([otherChip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Other Page"] &&
              [otherChip->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"other.example"],
              "an @-mentioned tab chip keeps its own title and domain");
        CHECK(otherChip->$__lazy_storage_$_iconView.image == otherIcon, "an @-mentioned tab chip keeps its own icon");

        peekPage.title = @"IANA-managed Reserved Domains";
        peekPage.url = [NSURL URLWithString:@"https://www.iana.org/domains/reserved"];
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"IANA-managed Reserved Domains"],
              "navigating inside Peek re-labels the chip title");
        CHECK([chip->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"iana.org"],
              "navigating inside Peek re-labels the chip domain without www.");

        NSImage *peekIcon = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        peekPage.favicon = peekIcon;
        [chip layout];
        CHECK(chip->$__lazy_storage_$_iconView.image == peekIcon, "the chip takes the Peek page favicon");
        peekPage.favicon = @"not-an-image";
        [chip layout];
        CHECK(chip->$__lazy_storage_$_iconView.image == parentIcon, "a non-image favicon falls back to Dia's own icon");

        peek.hidden = YES;
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Parent Page"] &&
              [chip->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"parent.example"],
              "hiding Peek restores the chip title and domain");
        CHECK(chip->$__lazy_storage_$_iconView.image == parentIcon, "hiding Peek restores the chip icon");
        peek.hidden = NO;
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"IANA-managed Reserved Domains"],
              "unhiding Peek puts the Peek page back in the chip");

        DPPeek.on = NO;
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Parent Page"] &&
              [chip->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"parent.example"] &&
              chip->$__lazy_storage_$_iconView.image == parentIcon,
              "turning Peek off restores the chip title, domain and icon");
        DPPeek.on = YES;
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"IANA-managed Reserved Domains"],
              "turning Peek back on re-labels the chip");

        chip->$__lazy_storage_$_titleView.stringValue = @"Parent Page Renamed";
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"IANA-managed Reserved Domains"],
              "a Dia re-render is overridden again on the next layout");
        DPPeek.on = NO;
        [chip layout];
        CHECK([chip->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Parent Page Renamed"],
              "the re-rendered title is what gets restored when Peek is off");
        DPPeek.on = YES;
        [chip layout];

        _TtC11Attachments18AttachmentCellView *reused = [[_TtC11Attachments18AttachmentCellView alloc] initWithFrame:NSMakeRect(0, 120, 184, 54)];
        reused->$__lazy_storage_$_titleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 16)];
        reused->$__lazy_storage_$_subtitleView = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 14)];
        reused->$__lazy_storage_$_iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        for (NSView *part in @[ reused->$__lazy_storage_$_titleView, reused->$__lazy_storage_$_subtitleView, reused->$__lazy_storage_$_iconView ])
            [reused addSubview:part];
        reused->$__lazy_storage_$_titleView.stringValue = @"Parent Page";
        reused->$__lazy_storage_$_subtitleView.stringValue = @"parent.example";
        NSImage *reusedIcon = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        reused->$__lazy_storage_$_iconView.image = reusedIcon;
        [window.contentView addSubview:reused];
        [reused layout];
        CHECK([reused->$__lazy_storage_$_titleView.stringValue isEqualToString:@"IANA-managed Reserved Domains"],
              "a same-domain chip is claimed for the Peek page before reuse");

        [reused prepareForReuse];
        CHECK([reused->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Parent Page"] &&
              [reused->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"parent.example"] &&
              reused->$__lazy_storage_$_iconView.image == reusedIcon,
              "prepareForReuse restores the chip's own title, domain and icon");

        reused->$__lazy_storage_$_titleView.stringValue = @"Sibling Page";
        reused->$__lazy_storage_$_subtitleView.stringValue = @"parent.example";
        [reused layout];
        CHECK([reused->$__lazy_storage_$_titleView.stringValue isEqualToString:@"Sibling Page"] &&
              [reused->$__lazy_storage_$_subtitleView.stringValue isEqualToString:@"parent.example"],
              "a reused same-domain chip is not claimed by Peek");
        [reused removeFromSuperview];

        [chip removeFromSuperview];
        [otherChip removeFromSuperview];

        int selBefore = kvo.selectedHits, inBefore = kvo.inputHits;
        peekPage.selectedText = @"highlighted-in-peek";
        CHECK(kvo.selectedHits == selBefore + 1 && kvo.inputHits == inBefore + 1, "Peek selection change notifies source KVO");
        CHECK([kvo.lastSeenSelected isEqualToString:@"highlighted-in-peek"], "source KVO observer immediately reads new Peek selection");

        int inLoadingStart = kvo.inputHits;
        peekPage.isLoading = YES;
        CHECK(kvo.inputHits == inLoadingStart, "starting load in Peek does not spuriously invalidate prefetch cache");
        peekPage.isLoading = NO;
        CHECK(kvo.inputHits == inLoadingStart + 1, "finishing load in Peek invalidates source prefetch cache");
        peekPage.url = [NSURL URLWithString:@"https://peek.example/next"];
        CHECK(kvo.inputHits == inLoadingStart + 2, "navigating inside Peek invalidates source prefetch cache");

        int hideSel = kvo.selectedHits, hideIn = kvo.inputHits;
        NSRect frameBeforeHide = peek.frame;
        peek.hidden = YES;
        CHECK(DPPeekCardIn(window) == nil, "hidden (parked) Peek is excluded from DPPeekCardIn");
        CHECK(kvo.selectedHits == hideSel + 1 && kvo.inputHits == hideIn + 1, "hiding Peek invalidates source cache and selection");
        CHECK([kvo.lastSeenSelected isEqualToString:@"parent-selection"], "source selection restores immediately when Peek hides");
        CHECK([source.title isEqualToString:@"Parent Page"], "hiding Peek restores the parent tab title in the chip");
        CHECK([source.url.absoluteString isEqualToString:@"https://parent.example/list"], "hiding Peek restores the parent tab URL in the chip");
        CHECK([source.favicon isEqual:@"parent-icon"], "hiding Peek restores the parent tab favicon in the chip");
        contentContainer.frame = NSMakeRect(0, 0, 700, 756);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane.frame = splitHost.bounds;
        [sidebarVC viewWillLayout];
        CHECK(NSEqualRects(peek.frame, frameBeforeHide), "sidebar layout skips parked hidden Peek cards");
        extracted = nil;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"parent"], "page extraction restores to parent while Peek is hidden");

        contentContainer.frame = NSMakeRect(0, 0, 1200, 756);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane.frame = splitHost.bounds;
        peek.hidden = NO;
        CHECK(DPPeekCardIn(window) == peek, "unhidden Peek returns to DPPeekCardIn");
        extracted = nil;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"peek"], "page extraction switches back to Peek when unhidden");

        _TtC11ContentPane15ContentPaneView *pane2 = [[_TtC11ContentPane15ContentPaneView alloc] initWithFrame:NSMakeRect(0, 0, 660, 756)];
        pane.hidden = YES;
        [pane removeFromSuperview];
        contentContainer.frame = NSMakeRect(0, 0, 660, 756);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        [splitHost addSubview:pane2];
        [sidebarVC viewWillLayout];
        CHECK(peek.pane == pane2, "followPane rebinds from detached ContentPaneView to live pane");
        CHECK(fabs(NSWidth(peek.frame) - 660) < 0.5, "Peek shrinks cleanly beside Side Chat even after ContentPaneView swap");
        contentContainer.frame = NSMakeRect(0, 0, 1200, 756);
        pageContainer.frame = contentContainer.bounds;
        splitHost.frame = pageContainer.bounds;
        pane2.frame = splitHost.bounds;
        [sidebarVC viewWillLayout];
        CHECK(fabs(NSWidth(peek.frame) - 1200) < 0.5, "Peek expands cleanly when Side Chat closes after rebind");
        [pane2 removeFromSuperview];
        pane.hidden = NO;
        pane.frame = splitHost.bounds;
        [splitHost addSubview:pane];
        [sidebarVC viewWillLayout];

        DPPeek.on = NO;
        extracted = nil;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"parent"] && [source.selectedText isEqualToString:@"parent-selection"],
              "off-tweak invariant: extraction and selection untouched when DPPeek.on == NO");
        CHECK(!DPPeekAllowsPaneClick(peek, chatBtnInWindow), "off-tweak invariant: hit-test pass-through disabled when off");
        CHECK(!DPPeekChatShortcut(peek, cmdE, NSEventModifierFlagCommand), "off-tweak invariant: chat shortcut disabled when off");
        CHECK([source.title isEqualToString:@"Parent Page"] && [source.favicon isEqual:@"parent-icon"],
              "off-tweak invariant: chip title and favicon untouched when DPPeek.on == NO");
        DPPeek.on = YES;

        int closeSel = kvo.selectedHits, closeIn = kvo.inputHits;
        [peek handOverTo:nil attach:nil];
        CHECK(peek.chatBridge == nil, "closing Peek clears chatBridge");
        CHECK(kvo.selectedHits == closeSel + 1 && kvo.inputHits == closeIn + 1, "closing Peek notifies source once to restore context");
        CHECK([kvo.lastSeenSelected isEqualToString:@"parent-selection"], "source selectedText restores to parent on Peek close");
        extracted = nil;
        [extractor getExtractedContentForWebContents:source completion:^(NSDictionary *c) { extracted = c; }];
        CHECK([extracted[@"tag"] isEqualToString:@"parent"], "page extraction restores to parent after Peek closes");
        CHECK([source.title isEqualToString:@"Parent Page"], "closing Peek restores the parent tab title in the chip");
        CHECK([source.url.absoluteString isEqualToString:@"https://parent.example/list"], "closing Peek restores the parent tab URL in the chip");
        CHECK([source.favicon isEqual:@"parent-icon"], "closing Peek restores the parent tab favicon in the chip");

        int afterCloseSel = kvo.selectedHits, afterCloseIn = kvo.inputHits;
        peekPage.selectedText = @"after-close";
        peekPage.isLoading = NO;
        peekPage.url = [NSURL URLWithString:@"about:blank"];
        CHECK(kvo.selectedHits == afterCloseSel && kvo.inputHits == afterCloseIn,
              "detached Peek page no longer forwards KVO to source");

        {
            ArcWebContents *orphanPeekPage = [ArcWebContents new];
            orphanPeekPage.tag = @"orphan";
            orphanPeekPage.selectedText = @"orphan-sel";
            @autoreleasepool {
                DPPeekCard *orphan = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
                orphan.page = orphanPeekPage;
                orphan.source = source;
                DPPeekChatAttach(orphan);
                CHECK(orphan.chatBridge != nil, "orphan card attached chatBridge");
                // Intentionally drop orphan without calling close: or handOverTo:.
            }
            int orphanSelBefore = kvo.selectedHits, orphanInBefore = kvo.inputHits;
            orphanPeekPage.selectedText = @"after-dealloc";
            orphanPeekPage.isLoading = NO;
            orphanPeekPage.url = [NSURL URLWithString:@"https://after-dealloc.example/"];
            CHECK(kvo.selectedHits == orphanSelBefore && kvo.inputHits == orphanInBefore,
                  "sudden DPPeekCard dealloc detaches KVO cleanly without crashing or notifying source");

            dispatch_queue_t bg = dispatch_queue_create("dp.peek.kvo.torture", DISPATCH_QUEUE_CONCURRENT);
            for (int iter = 0; iter < 50; iter++) {
                ArcWebContents *racePage = [ArcWebContents new];
                racePage.tag = @"race";
                DPPeekCard *raceCard = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
                raceCard.page = racePage;
                raceCard.source = source;
                DPPeekChatAttach(raceCard);
                id bridge = raceCard.chatBridge;
                dispatch_async(bg, ^{
                    racePage.selectedText = @"bg-sel";
                    racePage.url = [NSURL URLWithString:@"https://race.example/"];
                });
                DPPeekChatDetach(raceCard);
                DPPeekChatDetach(raceCard); // idempotent double detach
                DPPeekChatDetachBridge(bridge);
            }
            dispatch_barrier_sync(bg, ^{});
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            CHECK(YES, "50 iterations of background KVO vs main-thread detach completed without crash or exception");

            DPPeekOpenFrom(window, @"tab-1", [NSURL URLWithString:@"https://peek.example/parked"], NSMakeRect(100, 100, 40, 20), nil, source, nil, nil);
            DPPeekCard *parked = DPPeekCardIn(window);
            parked.hidden = YES;
            int parkedSel = kvo.selectedHits, parkedIn = kvo.inputHits;
            DPPeekCloseForSource(source);
            CHECK(parked.closing && parked.chatBridge == nil && kvo.selectedHits == parkedSel && kvo.inputHits == parkedIn,
                  "DPPeekCloseForSource detaches parked Peek quietly without synthetic KVO on dying source");
        }

        {
            ArcWebContents *srcA = [ArcWebContents new], *srcB = [ArcWebContents new], *srcC = [ArcWebContents new];
            srcA.tag = @"tabA"; srcA.title = @"tabA"; srcA.url = [NSURL URLWithString:@"https://tabA.example/"]; srcA.selectedText = @"sel-A";
            srcB.tag = @"tabB"; srcB.title = @"tabB"; srcB.url = [NSURL URLWithString:@"https://tabB.example/"]; srcB.selectedText = @"sel-B";
            srcC.tag = @"tabC"; srcC.title = @"tabC"; srcC.url = [NSURL URLWithString:@"https://tabC.example/"]; srcC.selectedText = @"sel-C";

            gActiveTabID = @"tab-A";
            DPPeekOpenFrom(window, @"tab-A", [NSURL URLWithString:@"https://peekA.example/"], NSMakeRect(100, 100, 40, 20), nil, srcA, nil, nil);
            DPPeekCard *peekA = DPPeekCardIn(window);
            ((ArcWebContents *)peekA.page).tag = @"peekA";
            ((ArcWebContents *)peekA.page).title = @"peekA";
            ((ArcWebContents *)peekA.page).selectedText = @"peekA-sel";

            __block NSDictionary *exA = nil, *exB = nil, *exC = nil;
            [extractor getExtractedContentForWebContents:srcA completion:^(NSDictionary *c) { exA = c; }];
            [extractor getExtractedContentForWebContents:srcB completion:^(NSDictionary *c) { exB = c; }];
            [extractor getExtractedContentForWebContents:srcC completion:^(NSDictionary *c) { exC = c; }];
            CHECK([exA[@"tag"] isEqualToString:@"peekA"] && [srcA.selectedText isEqualToString:@"peekA-sel"], "Tab A active -> routes to Peek A");
            CHECK([exB[@"tag"] isEqualToString:@"tabB"] && [srcB.selectedText isEqualToString:@"sel-B"], "Tab B unaffected while Peek A active");
            CHECK([exC[@"tag"] isEqualToString:@"tabC"] && [srcC.selectedText isEqualToString:@"sel-C"], "Tab C unaffected while Peek A active");

            gActiveTabID = @"tab-B";
            peekA.hidden = YES;
            [extractor getExtractedContentForWebContents:srcA completion:^(NSDictionary *c) { exA = c; }];
            [extractor getExtractedContentForWebContents:srcB completion:^(NSDictionary *c) { exB = c; }];
            CHECK([exA[@"tag"] isEqualToString:@"tabA"] && [exB[@"tag"] isEqualToString:@"tabB"], "Tab B active -> zero stale Peek A context");

            gActiveTabID = @"tab-C";
            DPPeekOpenFrom(window, @"tab-C", [NSURL URLWithString:@"https://peekC.example/"], NSMakeRect(100, 100, 40, 20), nil, srcC, nil, nil);
            DPPeekCard *peekC = DPPeekCardIn(window);
            ((ArcWebContents *)peekC.page).tag = @"peekC";
            ((ArcWebContents *)peekC.page).title = @"peekC";
            ((ArcWebContents *)peekC.page).selectedText = @"peekC-sel";
            [extractor getExtractedContentForWebContents:srcA completion:^(NSDictionary *c) { exA = c; }];
            [extractor getExtractedContentForWebContents:srcB completion:^(NSDictionary *c) { exB = c; }];
            [extractor getExtractedContentForWebContents:srcC completion:^(NSDictionary *c) { exC = c; }];
            CHECK([exC[@"tag"] isEqualToString:@"peekC"] && [srcC.selectedText isEqualToString:@"peekC-sel"], "Tab C active -> routes to Peek C");
            CHECK([srcC.title isEqualToString:@"tabC"] && [srcA.title isEqualToString:@"tabA"],
                  "each tab keeps its own title while another tab's Peek is open");
            CHECK([exA[@"tag"] isEqualToString:@"tabA"] && [exB[@"tag"] isEqualToString:@"tabB"], "parked Peek A and Tab B stay isolated on Tab C");

            [peekA handOverTo:nil attach:nil];
            [peekC handOverTo:nil attach:nil];
            gActiveTabID = @"tab-1";
        }

        [source removeObserver:kvo forKeyPath:@"selectedText"];
        [source removeObserver:kvo forKeyPath:@"inputEvent"];

        if (failures) return 1;
        puts("PASS: Peek AI Side Chat shortcuts, hit-test, layout, context routing, KVO sync, and off-tweak invariant");
    }
    return 0;
}
