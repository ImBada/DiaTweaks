#import "Patches/DestinationToggleEngineName/DestinationToggleEngineName.m"

// Dia's own classes, faked: ArcBrowser -context → ArcBrowserContext -preferences →
// ArcBrowserContextPreferences -getDefaultSearchEngine → ArcSearchEngine -name.
@interface ArcSearchEngine : NSObject
@property (copy) NSString *name;
@end
@implementation ArcSearchEngine
@end

@interface ArcBrowserContextPreferences : NSObject
@property (strong) ArcSearchEngine *engine;
@end
@implementation ArcBrowserContextPreferences
- (id)getDefaultSearchEngine { return self.engine; }
@end

@interface ArcBrowserContext : NSObject
@property (strong) ArcBrowserContextPreferences *preferences;
@end
@implementation ArcBrowserContext
@end

@interface ArcBrowser : NSObject {
@public
    __weak NSWindow *_window;
}
@property (strong) ArcBrowserContext *context;
- (void)setWindow:(NSWindow *)window;
@end
@implementation ArcBrowser
- (void)setWindow:(NSWindow *)window { _window = window; }
@end

@interface _TtC13NavigationBar13ToggleControl : NSControl
@property (strong) NSTextField *titleField;
@property NSInteger invalidations;
@end
@implementation _TtC13NavigationBar13ToggleControl
- (void)updateLayer {}
- (void)invalidateIntrinsicContentSize { self.invalidations++; [super invalidateIntrinsicContentSize]; }
@end

@interface _TtC13NavigationBar16AssistantBarView : NSView
@end
@implementation _TtC13NavigationBar16AssistantBarView
- (void)layout { [super layout]; }
@end

@interface _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView : NSView
@end
@implementation _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView
@end

@interface DPTestWindow : NSWindow
@end
@implementation DPTestWindow
- (BOOL)isVisible { return YES; }
@end

static int failures;

static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

static void checkText(const char *what, NSView *view, NSString *expected) {
    NSString *text = DPTextOf(view);
    if (![text isEqualToString:expected]) printf("FAIL: %s: got “%s”, wanted “%s”\n", what, text.UTF8String ?: "(nil)", expected.UTF8String), failures++;
}

static DPTestWindow *DPWindow(void) {
    return [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 800) styleMask:NSWindowStyleMaskBorderless
                                             backing:NSBackingStoreBuffered defer:NO];
}

static ArcBrowser *DPBrowser(NSWindow *window, NSString *engine) {
    ArcSearchEngine *search = [ArcSearchEngine new];
    search.name = engine;
    ArcBrowserContextPreferences *preferences = [ArcBrowserContextPreferences new];
    preferences.engine = search;
    ArcBrowserContext *context = [ArcBrowserContext new];
    context.preferences = preferences;
    ArcBrowser *browser = [ArcBrowser new];
    browser.context = context;
    [browser setWindow:window];
    return browser;
}

static ArcSearchEngine *DPEngineOf(ArcBrowser *browser) {
    return browser.context.preferences.engine;
}

// An address field with the Chat toggle's capsule and, beside it, the page title Dia also draws there.
static _TtC13NavigationBar16AssistantBarView *DPField(NSWindow *window, _TtC13NavigationBar13ToggleControl **toggleOut, NSTextField **titleOut) {
    _TtC13NavigationBar16AssistantBarView *field = [[_TtC13NavigationBar16AssistantBarView alloc] initWithFrame:NSMakeRect(0, 0, 600, 32)];
    _TtC13NavigationBar13ToggleControl *toggle = [[_TtC13NavigationBar13ToggleControl alloc] initWithFrame:NSMakeRect(0, 0, 60, 24)];
    NSTextField *capsule = [NSTextField labelWithString:@"Google"];
    [toggle addSubview:capsule];
    toggle.titleField = capsule;
    [field addSubview:toggle];
    NSTextField *title = [NSTextField labelWithString:@"Google"];
    [field addSubview:title];
    [window.contentView addSubview:field];
    if (toggleOut) *toggleOut = toggle;
    if (titleOut) *titleOut = title;
    return field;
}

// The Chat/Search dropdown: an NSPopover whose content lives in its own child window, as a real popover's does.
static NSPopover *DPDropdown(NSWindow *parent, NSTextField **chatOut, NSTextField **googleOut, NSWindow **childOut) {
    DPTestWindow *child = DPWindow();
    [parent addChildWindow:child ordered:NSWindowAbove];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
    NSTextField *chat = [NSTextField labelWithString:@"Chat"];
    NSTextField *google = [NSTextField labelWithString:@"Google"];
    [content addSubview:chat];
    [content addSubview:google];
    [child.contentView addSubview:content];
    NSViewController *controller = [NSViewController new];
    controller.view = content;
    NSPopover *popover = [NSPopover new];
    popover.contentViewController = controller;
    if (chatOut) *chatOut = chat;
    if (googleOut) *googleOut = google;
    if (childOut) *childOut = child;
    return popover;
}

static NSMenu *DPMenu(NSMenuItem **chatOut, NSMenuItem **googleOut) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Destination"];
    NSMenuItem *chat = [[NSMenuItem alloc] initWithTitle:@"Chat" action:nil keyEquivalent:@""];
    NSMenuItem *google = [[NSMenuItem alloc] initWithTitle:@"Google" action:nil keyEquivalent:@""];
    [menu addItem:chat];
    [menu addItem:google];
    if (chatOut) *chatOut = chat;
    if (googleOut) *googleOut = google;
    return menu;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPDestinationToggleEngineName.install();

        // Dia's Settings window is first in NSApp.windows and has no toggle: the sweep must survive it.
        DPTestWindow *settings = DPWindow();
        [settings.contentView addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)]];

        DPTestWindow *window = DPWindow();
        ArcBrowser *browser = DPBrowser(window, @"Kagi");
        _TtC13NavigationBar13ToggleControl *toggle;
        NSTextField *title;
        _TtC13NavigationBar16AssistantBarView *field = DPField(window, &toggle, &title);

        DPDestinationToggleEngineName.on = NO;
        toggle.invalidations = 0;
        [field layout];
        checkText("off leaves Google", toggle.titleField, @"Google");
        check("off invalidates nothing", toggle.invalidations == 0);

        DPDestinationToggleEngineName.on = YES;
        [field layout];
        checkText("Kagi in the capsule", toggle.titleField, @"Kagi");
        checkText("page title untouched", title, @"Google");
        check("a longer name is measured again", toggle.invalidations > 0);

        NSArray<NSString *> *names = @[ @"DuckDuckGo", @"Brave", @"Bing", @"Ecosia", @"Startpage", @"My Search" ];
        for (NSString *name in names) {
            DPEngineOf(browser).name = name;
            [field layout];
            checkText(name.UTF8String, toggle.titleField, name);
        }

        DPEngineOf(browser).name = @"Google";
        [field layout];
        checkText("Google stays Google", toggle.titleField, @"Google");

        DPEngineOf(browser).name = nil;
        [field layout];
        checkText("nil engine falls back", toggle.titleField, @"Google");
        DPEngineOf(browser).name = @"";
        [field layout];
        checkText("empty engine falls back", toggle.titleField, @"Google");
        DPEngineOf(browser).name = @"   ";
        [field layout];
        checkText("blank engine falls back", toggle.titleField, @"Google");
        DPEngineOf(browser).name = @"  Kagi  ";
        [field layout];
        checkText("engine name is trimmed", toggle.titleField, @"Kagi");

        DPTestWindow *other = DPWindow();
        ArcBrowser *otherBrowser = DPBrowser(other, @"DuckDuckGo");
        _TtC13NavigationBar13ToggleControl *otherToggle;
        _TtC13NavigationBar16AssistantBarView *otherField = DPField(other, &otherToggle, NULL);
        [field layout];
        [otherField layout];
        checkText("first profile keeps Kagi", toggle.titleField, @"Kagi");
        checkText("second profile gets DuckDuckGo", otherToggle.titleField, @"DuckDuckGo");
        DPEngineOf(otherBrowser).name = @"Startpage";
        [otherField layout];
        checkText("second profile follows its engine", otherToggle.titleField, @"Startpage");
        checkText("first profile is unaffected", toggle.titleField, @"Kagi");

        DPEngineOf(browser).name = @"Ecosia";
        [field layout];
        checkText("engine change lands", toggle.titleField, @"Ecosia");

        DPDestinationToggleEngineName.on = NO;
        [field layout];
        checkText("off restores Google", toggle.titleField, @"Google");
        DPDestinationToggleEngineName.on = YES;
        [field layout];
        checkText("on again", toggle.titleField, @"Ecosia");

        // The dropdown's content sits in a child window, so the engine resolves through parentWindow: the child is never in DPBrowsers.
        NSTextField *chatRow, *googleRow;
        NSWindow *child;
        NSPopover *dropdown = DPDropdown(window, &chatRow, &googleRow, &child);
        NSView *content = dropdown.contentViewController.view;
        check("popover content is in its own window", content.window == child);
        check("that window is a child of the browser window", child.parentWindow == window);
        check("the child window is not the browser's", [DPBrowsers objectForKey:child] == nil);
        check("engine resolves through the child window", [DPEngineNameForWindow(child) isEqualToString:@"Ecosia"]);
        DPApplyEngineNameToView(content, nil);
        checkText("Chat row untouched", chatRow, @"Chat");
        checkText("Google row renamed through the child window", googleRow, @"Ecosia");
        DPEngineOf(browser).name = @"Kagi";
        DPApplyEngineNameToView(content, nil);
        checkText("Google row follows a new engine", googleRow, @"Kagi");
        DPDestinationToggleEngineName.on = NO;
        DPApplyEngineNameToView(content, nil);
        checkText("Google row restored", googleRow, @"Google");
        DPDestinationToggleEngineName.on = YES;
        DPApplyEngineNameToView(content, nil);
        checkText("Google row renamed again", googleRow, @"Kagi");
        DPEngineOf(browser).name = @"Ecosia";

        NSView *detached = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
        NSTextField *detachedChat = [NSTextField labelWithString:@"Chat"];
        NSTextField *detachedGoogle = [NSTextField labelWithString:@"Google"];
        [detached addSubview:detachedChat];
        [detached addSubview:detachedGoogle];
        check("detached content has no window", detached.window == nil);
        DPApplyEngineNameToView(detached, window);
        checkText("detached Google row renamed from the anchor window", detachedGoogle, @"Ecosia");

        NSMenuItem *chatItem, *googleItem;
        NSMenu *menu = DPMenu(&chatItem, &googleItem);
        check("menu relabel from the address field", DPApplyMenu(menu, toggle));
        check("Chat item untouched", [chatItem.title isEqualToString:@"Chat"]);
        check("Google item renamed", [googleItem.title isEqualToString:@"Ecosia"]);
        DPEngineOf(browser).name = @"Kagi";
        DPApplyMenu(menu, toggle);
        check("Google item follows a new engine", [googleItem.title isEqualToString:@"Kagi"]);
        DPDestinationToggleEngineName.on = NO;
        DPApplyMenu(menu, toggle);
        check("Google item restored", [googleItem.title isEqualToString:@"Google"]);
        DPDestinationToggleEngineName.on = YES;
        DPApplyMenu(menu, toggle);
        check("Google item renamed again", [googleItem.title isEqualToString:@"Kagi"]);
        DPEngineOf(browser).name = @"Ecosia";

        NSMenuItem *outsideChat, *outsideGoogle;
        NSMenu *outside = DPMenu(&outsideChat, &outsideGoogle);
        NSView *pageView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [window.contentView addSubview:pageView];
        check("outside menu is left alone", !DPApplyMenu(outside, pageView));
        check("outside Google item untouched", [outsideGoogle.title isEqualToString:@"Google"]);

        NSMenu *siteMenu = [[NSMenu alloc] initWithTitle:@"Site"];
        NSMenuItem *siteItem = [[NSMenuItem alloc] initWithTitle:@"Google" action:nil keyEquivalent:@""];
        [siteMenu addItem:siteItem];
        check("address-field menu without Chat is left alone", !DPApplyMenu(siteMenu, toggle));
        check("its Google item untouched", [siteItem.title isEqualToString:@"Google"]);

        _TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView *dynamic =
            [[_TtCC14DynamicPopover28DynamicPopoverViewControllerP33_AB0357A1429F4D6D7F128058B713C93F8RootView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
        NSTextField *dynamicChat = [NSTextField labelWithString:@"Chat"];
        NSTextField *dynamicGoogle = [NSTextField labelWithString:@"Google"];
        [dynamic addSubview:dynamicChat];
        [dynamic addSubview:dynamicGoogle];
        [window.contentView addSubview:dynamic];
        [dynamic layout];
        checkText("dynamic Chat row untouched", dynamicChat, @"Chat");
        checkText("dynamic Google row renamed", dynamicGoogle, @"Ecosia");

        NSView *lookalike = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
        NSTextField *lookalikeChat = [NSTextField labelWithString:@"Chat"];
        NSTextField *lookalikeGoogle = [NSTextField labelWithString:@"Google"];
        [lookalike addSubview:lookalikeChat];
        [lookalike addSubview:lookalikeGoogle];
        [window.contentView addSubview:lookalike];
        [lookalike layout];
        checkText("lookalike untouched", lookalikeGoogle, @"Google");

        toggle.accessibilityLabel = @"Google destination in the navigation bar destination toggle";
        toggle.toolTip = @"Click to toggle between Chat and Google";
        [field layout];
        check("accessibility label renamed", [toggle.accessibilityLabel isEqualToString:@"Ecosia destination in the navigation bar destination toggle"]);
        check("tooltip renamed", [toggle.toolTip isEqualToString:@"Click to toggle between Chat and Ecosia"]);
        DPEngineOf(browser).name = @"Kagi";
        [field layout];
        check("accessibility label follows a new engine", [toggle.accessibilityLabel isEqualToString:@"Kagi destination in the navigation bar destination toggle"]);
        check("tooltip follows a new engine", [toggle.toolTip isEqualToString:@"Click to toggle between Chat and Kagi"]);
        DPEngineOf(browser).name = @"Ecosia";
        [field layout];
        DPDestinationToggleEngineName.on = NO;
        [field layout];
        check("accessibility label restored", [toggle.accessibilityLabel isEqualToString:@"Google destination in the navigation bar destination toggle"]);
        check("tooltip restored", [toggle.toolTip isEqualToString:@"Click to toggle between Chat and Google"]);
        DPDestinationToggleEngineName.on = YES;

        // Mutation check: a capsule that is never laid out keeps Dia's word, so the checks above fail once the hook stops running.
        _TtC13NavigationBar13ToggleControl *unhooked;
        _TtC13NavigationBar16AssistantBarView *unhookedField = DPField(window, &unhooked, NULL);
        checkText("mutation check: no layout, no rename", unhooked.titleField, @"Google");
        [field layout];
        checkText("mutation check: the hook is what renames", toggle.titleField, @"Ecosia");
        [unhookedField layout];
        checkText("mutation check: the hook renames the other capsule too", unhooked.titleField, @"Ecosia");

        DPTestWindow *orphan = DPWindow();
        _TtC13NavigationBar13ToggleControl *orphanToggle;
        _TtC13NavigationBar16AssistantBarView *orphanField = DPField(orphan, &orphanToggle, NULL);
        [orphanField layout];
        checkText("no browser falls back", orphanToggle.titleField, @"Google");
        check("no browser resolves nothing", DPEngineNameForWindow(orphan) == nil);
        check("display name falls back", [DPEngineDisplayName(nil) isEqualToString:@"Google"]);

        // Dia's Settings window is first in NSApp.windows; clearing the "we changed something" flag there used to leave every browser window unrestored.
        DPTestWindow *first = DPWindow();
        ArcBrowser *firstBrowser = DPBrowser(first, @"Kagi");
        _TtC13NavigationBar13ToggleControl *firstToggle;
        _TtC13NavigationBar16AssistantBarView *firstField = DPField(first, &firstToggle, NULL);
        DPTestWindow *second = DPWindow();
        ArcBrowser *secondBrowser = DPBrowser(second, @"DuckDuckGo");
        _TtC13NavigationBar13ToggleControl *secondToggle;
        _TtC13NavigationBar16AssistantBarView *secondField = DPField(second, &secondToggle, NULL);
        DPDestinationToggleEngineName.on = YES;
        DPApplyEngineNameToWindows();
        checkText("sweep renames the first window", firstToggle.titleField, @"Kagi");
        checkText("sweep renames the second window", secondToggle.titleField, @"DuckDuckGo");
        check("the sweep starts on a window with no toggle", DPFindView(NSApp.windows.firstObject.contentView, ^BOOL(NSView *v) {
            return DPIsKind(v, DPDiaToggleControl);
        }) == nil);
        DPDestinationToggleEngineName.on = NO;
        DPApplyEngineNameToWindows();
        checkText("off restores the first window", firstToggle.titleField, @"Google");
        checkText("off restores the second window", secondToggle.titleField, @"Google");
        checkText("off restores the earlier window", toggle.titleField, @"Google");
        check("off leaves nothing to sweep", DPApplied == NO);
        DPDestinationToggleEngineName.on = YES;
        DPApplyEngineNameToWindows();
        checkText("on again renames the first window", firstToggle.titleField, @"Kagi");
        checkText("on again renames the second window", secondToggle.titleField, @"DuckDuckGo");
        (void)firstBrowser;
        (void)secondBrowser;
        (void)firstField;
        (void)secondField;

        // Dia's onboarding tooltip names the engine inside one sentence, so it has no separate "Chat"/"Google" rows for the row-based pass.
        NSView *tooltip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 60)];
        NSTextField *tooltipTitle = [NSTextField labelWithString:@"Not the answer you wanted?"];
        NSTextField *tooltipSentence = [NSTextField labelWithString:@"Click to toggle between Chat and Google"];
        [tooltip addSubview:tooltipTitle];
        [tooltip addSubview:tooltipSentence];
        [window.contentView addSubview:tooltip];
        DPEngineOf(browser).name = @"Kagi";
        DPApplyEngineNameToView(tooltip, window);
        checkText("tooltip title untouched", tooltipTitle, @"Not the answer you wanted?");
        checkText("tooltip sentence names the engine", tooltipSentence, @"Click to toggle between Chat and Kagi");
        DPEngineOf(browser).name = @"DuckDuckGo";
        DPApplyEngineNameToView(tooltip, window);
        checkText("tooltip sentence follows a new engine", tooltipSentence, @"Click to toggle between Chat and DuckDuckGo");
        DPDestinationToggleEngineName.on = NO;
        DPApplyEngineNameToView(tooltip, window);
        checkText("tooltip sentence restored", tooltipSentence, @"Click to toggle between Chat and Google");
        DPDestinationToggleEngineName.on = YES;
        DPApplyEngineNameToView(tooltip, window);
        checkText("tooltip sentence renamed again", tooltipSentence, @"Click to toggle between Chat and DuckDuckGo");
        DPEngineOf(browser).name = @"Google";
        DPApplyEngineNameToView(tooltip, window);
        checkText("a Google profile keeps the sentence", tooltipSentence, @"Click to toggle between Chat and Google");
        DPEngineOf(browser).name = @"Ecosia";

        NSView *notTooltip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 40)];
        NSTextField *otherSentence = [NSTextField labelWithString:@"Chat and Google are different"];
        [notTooltip addSubview:otherSentence];
        [window.contentView addSubview:notTooltip];
        DPApplyEngineNameToView(notTooltip, window);
        checkText("a lookalike sentence is untouched", otherSentence, @"Chat and Google are different");

        check("disabled by hideToolbar", [DPDestinationToggleEngineName.disabledBy isEqualToString:@"hideToolbar"]);

        check("verify passes", DPDestinationToggleEngineName.verify(&DPDestinationToggleEngineName) == nil);
        toggle.titleField.stringValue = @"Google";
        check("verify catches Google", DPDestinationToggleEngineName.verify(&DPDestinationToggleEngineName) != nil);
        [field layout];

        if (failures) printf("%d failure(s)\n", failures);
        else printf("destination-toggle-engine-name: all checks passed\n");
        return failures ? 1 : 0;
    }
}
