#define DPFindViews DPRealFindViews
#import "StdPatch/Views.m"
#undef DPFindViews
#import "StdPatch/Hook.m"

static NSArray<NSView *> *visibleTabs;
static NSArray<NSView *> *visibleContents;

NSArray<NSView *> *DPFindViews(const char *name) {
    if (strcmp(name, DPDiaTabView) == 0) return visibleTabs ?: @[];
    if (strcmp(name, DPDiaTabContentView) == 0) return visibleContents ?: @[];
    return @[];
}

#import "Patches/PinnedTabCloseButton/PinnedTabCloseButton.m"

@interface _TtC5TabUI33TabWebContentAttributesController : NSObject {
@public
    BOOL isInFavoritesOrPinnedContainer;
}
@end
@implementation _TtC5TabUI33TabWebContentAttributesController
@end

@interface _TtC5TabUI7TabView : NSView {
@public
    id controller;
    int layoutCalls;
}
@end
@implementation _TtC5TabUI7TabView
- (void)layout {
    [super layout];
    layoutCalls++;
}
@end

@interface _TtC5TabUI14TabContentView : NSView {
@public
    id attributes;
}
@end
@implementation _TtC5TabUI14TabContentView
@end

@interface _TtC5ARCUI16ViewHoverTracker : NSObject {
@public
    __weak NSView *view;
    int enterCalls;
}
- (void)mouseEntered:(NSEvent *)event;
@end
@implementation _TtC5ARCUI16ViewHoverTracker
- (void)mouseEntered:(NSEvent *)event { enterCalls++; }
@end

@interface DPController158 : NSObject {
@public
    BOOL suppressesCloseButton;
    uint8_t requestedCloseButtonStyle;
}
@end
@implementation DPController158
@end

@interface DPController159 : NSObject {
@public
    uint8_t requestedCloseButtonStyle;
}
@end
@implementation DPController159
@end

@interface DPControllerUnknown : NSObject
@end
@implementation DPControllerUnknown
@end

id DPViewModelDelegate(NSView *view) {
    return [view isKindOfClass:_TtC5TabUI7TabView.class] ? ((_TtC5TabUI7TabView *)view)->controller : nil;
}

NSView *DPEnclosingTab(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
    return view;
}

void DPRelayoutTabContents(void) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) content.needsLayout = YES;
}

id DPAttributes(NSView *content) {
    return [content isKindOfClass:_TtC5TabUI14TabContentView.class] ? ((_TtC5TabUI14TabContentView *)content)->attributes : nil;
}

static _TtC5TabUI7TabView *NewTab(id controller, BOOL pinned, _TtC5TabUI14TabContentView **outContent, _TtC5TabUI33TabWebContentAttributesController **outAttrs) {
    _TtC5TabUI7TabView *tab = [[_TtC5TabUI7TabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
    tab->controller = controller;
    _TtC5TabUI33TabWebContentAttributesController *attrs = [_TtC5TabUI33TabWebContentAttributesController new];
    attrs->isInFavoritesOrPinnedContainer = pinned;
    _TtC5TabUI14TabContentView *content = [[_TtC5TabUI14TabContentView alloc] initWithFrame:tab.bounds];
    content->attributes = attrs;
    [tab addSubview:content];
    [tab layoutSubtreeIfNeeded];
    tab->layoutCalls = 0;
    if (outContent) *outContent = content;
    if (outAttrs) *outAttrs = attrs;
    return tab;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPInstallPinnedTabCloseButton();

        // Dia 1.58: TabController has suppressesCloseButton and requestedCloseButtonStyle.
        DPController158 *cPinned = [DPController158 new];
        cPinned->suppressesCloseButton = YES;
        cPinned->requestedCloseButtonStyle = 0;

        DPController158 *cUnpinnedLater = [DPController158 new];
        cUnpinnedLater->suppressesCloseButton = YES;
        cUnpinnedLater->requestedCloseButtonStyle = 0;

        DPController158 *cAlreadyAllowed = [DPController158 new];
        cAlreadyAllowed->suppressesCloseButton = NO;
        cAlreadyAllowed->requestedCloseButtonStyle = 1;

        _TtC5TabUI14TabContentView *contentPinned = nil, *contentUnpinned = nil, *contentAllowed = nil;
        _TtC5TabUI33TabWebContentAttributesController *attrsUnpinned = nil;
        _TtC5TabUI7TabView *tPinned = NewTab(cPinned, YES, &contentPinned, NULL);
        _TtC5TabUI7TabView *tUnpinned = NewTab(cUnpinnedLater, YES, &contentUnpinned, &attrsUnpinned);
        _TtC5TabUI7TabView *tAllowed = NewTab(cAlreadyAllowed, YES, &contentAllowed, NULL);

        _TtC5ARCUI16ViewHoverTracker *tracker = [_TtC5ARCUI16ViewHoverTracker new];
        tracker->view = contentPinned;

        visibleTabs = @[tPinned, tUnpinned, tAllowed];
        visibleContents = @[contentPinned, contentUnpinned, contentAllowed];

        [tPinned layout];
        [tracker mouseEntered:nil];
        CHECK(tPinned->layoutCalls == 1 && tracker->enterCalls == 1, "original hooks run while off");
        CHECK(cPinned->suppressesCloseButton == YES && DPCleared.count == 0, "off tweak leaves suppressesCloseButton untouched");
        CHECK(DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.58 verifies while off");

        DPPinnedTabCloseButton.on = YES;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        [tPinned layoutSubtreeIfNeeded];
        [tUnpinned layoutSubtreeIfNeeded];
        [tAllowed layoutSubtreeIfNeeded];
        CHECK(!tPinned.needsLayout && !tUnpinned.needsLayout && !tAllowed.needsLayout, "1.58 tabs settled layout");
        CHECK(!cPinned->suppressesCloseButton && !cUnpinnedLater->suppressesCloseButton && !cAlreadyAllowed->suppressesCloseButton,
              "1.58 ON clears suppressesCloseButton on suppressed tabs");
        CHECK(DPCleared.count == 2 && [DPCleared containsObject:cPinned] && [DPCleared containsObject:cUnpinnedLater]
              && ![DPCleared containsObject:cAlreadyAllowed],
              "1.58 tracks only tabs this tweak changed");
        CHECK(DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.58 verifies while ON");

        cPinned->suppressesCloseButton = YES;
        CHECK(DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) != nil, "1.58 verify catches suppressed pinned tab while ON");
        [tPinned layout];
        CHECK(!cPinned->suppressesCloseButton, "layout re-clears suppressesCloseButton while ON");
        cPinned->suppressesCloseButton = YES;
        [tracker mouseEntered:nil];
        CHECK(!cPinned->suppressesCloseButton, "mouseEntered re-clears suppressesCloseButton while ON");

        attrsUnpinned->isInFavoritesOrPinnedContainer = NO;
        DPPinnedTabCloseButton.on = NO;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        [tPinned layoutSubtreeIfNeeded];
        [tUnpinned layoutSubtreeIfNeeded];
        [tAllowed layoutSubtreeIfNeeded];
        CHECK(cPinned->suppressesCloseButton == YES, "1.58 OFF restores suppressesCloseButton on pinned tab");
        CHECK(cUnpinnedLater->suppressesCloseButton == NO, "1.58 OFF does not suppress tab unpinned while ON");
        CHECK(cAlreadyAllowed->suppressesCloseButton == NO, "1.58 OFF leaves pre-allowed tab unsuppressed");
        CHECK(DPCleared.count == 0, "1.58 OFF empties DPCleared");
        CHECK(DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.58 verifies after OFF");

        [tPinned layout];
        [tracker mouseEntered:nil];
        CHECK(cPinned->suppressesCloseButton == YES && DPCleared.count == 0, "hooks stay inert after turning OFF");

        // Dia 1.59: suppressesCloseButton removed, requestedCloseButtonStyle present.
        DPController159 *c159 = [DPController159 new];
        c159->requestedCloseButtonStyle = 1;
        _TtC5TabUI14TabContentView *content159 = nil;
        _TtC5TabUI7TabView *t159 = NewTab(c159, YES, &content159, NULL);
        _TtC5ARCUI16ViewHoverTracker *tracker159 = [_TtC5ARCUI16ViewHoverTracker new];
        tracker159->view = content159;

        visibleTabs = @[t159];
        visibleContents = @[content159];

        CHECK(!t159.needsLayout && DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.59 verifies while OFF");
        DPPinnedTabCloseButton.on = YES;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        [t159 layoutSubtreeIfNeeded];
        [t159 layout];
        [tracker159 mouseEntered:nil];
        CHECK(c159->requestedCloseButtonStyle == 1 && DPCleared.count == 0, "1.59 ON safely no-ops without mutating style");
        CHECK(!t159.needsLayout && DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.59 verifies while ON");

        DPPinnedTabCloseButton.on = NO;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        [t159 layoutSubtreeIfNeeded];
        CHECK(c159->requestedCloseButtonStyle == 1 && DPCleared.count == 0, "1.59 OFF safely no-ops");
        CHECK(!t159.needsLayout && DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "1.59 verifies after OFF");

        DPControllerUnknown *cUnknown = [DPControllerUnknown new];
        _TtC5TabUI14TabContentView *contentUnknown = nil;
        _TtC5TabUI7TabView *tUnknown = NewTab(cUnknown, YES, &contentUnknown, NULL);
        visibleTabs = @[tUnknown];
        visibleContents = @[contentUnknown];

        CHECK(!tUnknown.needsLayout && DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) != nil, "unknown controller fails verify while OFF");
        DPPinnedTabCloseButton.on = YES;
        CHECK(!tUnknown.needsLayout && DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) != nil, "unknown controller fails verify while ON");
        tUnknown.needsLayout = YES;
        CHECK(DPVerifyPinnedTabCloseButton(&DPPinnedTabCloseButton) == nil, "pending layout tab is skipped by verify");
        DPPinnedTabCloseButton.on = NO;

        visibleTabs = @[];
        visibleContents = @[];
        NSWindow *hidden = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        hidden.releasedWhenClosed = NO;
        DPController158 *cHidden = [DPController158 new];
        cHidden->suppressesCloseButton = YES;
        _TtC5TabUI14TabContentView *contentHidden = nil;
        _TtC5TabUI7TabView *tHidden = NewTab(cHidden, YES, &contentHidden, NULL);
        [hidden.contentView addSubview:tHidden];
        DPPinnedTabCloseButton.on = YES;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        CHECK(!cHidden->suppressesCloseButton, "hidden window tab clears suppressesCloseButton on apply ON");
        DPPinnedTabCloseButton.on = NO;
        DPApplyPinnedTabCloseButton(&DPPinnedTabCloseButton);
        CHECK(cHidden->suppressesCloseButton, "hidden window tab restores suppressesCloseButton on apply OFF");
        [hidden close];
    }
    if (failures) return 1;
    puts("PASS: pinned-tab-close-button");
    return 0;
}
