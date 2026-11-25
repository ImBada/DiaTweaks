#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"

static const CGFloat DPLauncherWidth = 420, DPLauncherHeight = 48, DPLauncherInset = 20;

@interface DPLittleDiaLauncherPanel : NSPanel
@end

@implementation DPLittleDiaLauncherPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface DPLittleDiaLauncherBackground : NSVisualEffectView
@end

@implementation DPLittleDiaLauncherBackground

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateBorder];
}

- (void)updateBorder {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 12;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1;
    __block NSColor *border;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        border = [NSColor.separatorColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    }];
    self.layer.borderColor = border.CGColor;
}

@end

@interface DPLittleDiaLauncherController : NSObject <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) DPLittleDiaLauncherPanel *panel;
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) id resignObserver;
@property (nonatomic) BOOL closing;
@end

static DPLittleDiaLauncherController *DPLauncher;

@implementation DPLittleDiaLauncherController

+ (DPLittleDiaLauncherController *)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ DPLauncher = [DPLittleDiaLauncherController new]; });
    return DPLauncher;
}

- (DPLittleDiaLauncherPanel *)makePanel {
    DPLittleDiaLauncherPanel *panel = [[DPLittleDiaLauncherPanel alloc] initWithContentRect:NSMakeRect(0, 0, DPLauncherWidth, DPLauncherHeight)
                                                                                 styleMask:NSWindowStyleMaskBorderless
                                                                                   backing:NSBackingStoreBuffered
                                                                                     defer:NO];
    panel.level = NSFloatingWindowLevel;
    panel.hasShadow = YES;
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.movableByWindowBackground = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    panel.delegate = self;

    DPLittleDiaLauncherBackground *background = [[DPLittleDiaLauncherBackground alloc] initWithFrame:NSMakeRect(0, 0, DPLauncherWidth, DPLauncherHeight)];
    background.material = NSVisualEffectMaterialHUDWindow;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    [background updateBorder];

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:15];
    field.placeholderString = @"Enter address or search…";
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *hint = [NSTextField labelWithString:@"↵"];
    hint.font = [NSFont systemFontOfSize:13];
    hint.textColor = NSColor.tertiaryLabelColor;
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    [background addSubview:icon];
    [background addSubview:field];
    [background addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [field.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [field.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [hint.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:8],
        [hint.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14],
        [hint.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
    ]];
    panel.contentView = background;
    panel.initialFirstResponder = field;
    self.field = field;
    return panel;
}

- (void)show {
    if (!DPLittleDia.on || !DPLittleDiaLauncher.on) return;
    if (!self.panel) self.panel = [self makePanel];
    self.closing = NO;
    self.field.stringValue = @"";
    NSScreen *screen = nil;
    NSPoint mouse = NSEvent.mouseLocation;
    for (NSScreen *each in NSScreen.screens)
        if (NSMouseInRect(mouse, each.frame, NO)) {
            screen = each;
            break;
        }
    NSRect visible = (screen ?: NSScreen.mainScreen).visibleFrame;
    NSRect frame = NSMakeRect(NSMaxX(visible) - DPLauncherWidth - DPLauncherInset, NSMaxY(visible) - DPLauncherHeight - DPLauncherInset,
                              DPLauncherWidth, DPLauncherHeight);
    [self.panel setFrame:frame display:NO];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.field];
    if (!self.resignObserver)
        self.resignObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidResignActiveNotification object:nil
                                                                              queue:NSOperationQueue.mainQueue
                                                                         usingBlock:^(NSNotification *note) { DPHideLittleDiaLauncher(); }];
}

- (void)close {
    if (self.closing) return;
    self.closing = YES;
    [self.panel orderOut:nil];
    if (self.resignObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.resignObserver];
        self.resignObserver = nil;
    }
    self.closing = NO;
}

- (void)submit {
    NSString *text = [self.field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = text.length ? (DPAddressURL(text) ?: DPLittleDiaSearchURL(text)) : nil;
    if (!url) return (void)NSBeep();
    [self close];
    DPOpenLinkInLittleDia(url);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command == @selector(insertNewline:)) {
        [self submit];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        [self close];
        return YES;
    }
    return NO;
}

- (void)windowDidResignKey:(NSNotification *)notification {
    if (notification.object == self.panel) [self close];
}

@end

BOOL DPLittleDiaLauncherVisible(void) { return DPLauncher.panel.isVisible; }

void DPShowLittleDiaLauncher(void) { [[DPLittleDiaLauncherController shared] show]; }

void DPToggleLittleDiaLauncher(void) {
    if (DPLittleDiaLauncherVisible()) [[DPLittleDiaLauncherController shared] close];
    else DPShowLittleDiaLauncher();
}

void DPHideLittleDiaLauncher(void) { [[DPLittleDiaLauncherController shared] close]; }

NSURL *DPLittleDiaSearchURL(NSString *text) {
    id browser = DPCommandBrowser();
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    id preferences = DPValueForKey(context, @"preferences");
    id engine = [preferences respondsToSelector:@selector(getDefaultSearchEngine)] ? DPMsg(preferences, @selector(getDefaultSearchEngine)) : nil;
    NSString *query = [text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    query = [query stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    query = [query stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    NSString *template = DPValueForKey(engine, @"url");
    if (![template isKindOfClass:NSString.class] || ![template containsString:@"{searchTerms}"] || [template containsString:@"{google:"])
        template = @"https://www.google.com/search?q={searchTerms}";
    template = [template stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:query];
    static NSRegularExpression *rest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ rest = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:nil]; });
    return [NSURL URLWithString:[rest stringByReplacingMatchesInString:template options:0 range:NSMakeRange(0, template.length) withTemplate:@""]];
}

static void DPApplyLittleDiaLauncher(DPPatch *patch) {
    if (!patch->on || !DPLittleDia.on) DPHideLittleDiaLauncher();
}

static NSString *DPVerifyLittleDiaLauncher(DPPatch *patch) {
    if (!patch->on && DPLittleDiaLauncherVisible()) return @"the launcher stayed open when turned off";
    return nil;
}

DP_PATCH(DPLittleDiaLauncher) {
    .key = @"littleDiaLauncher",
    .defaultOn = YES,
    .order = 104,
    .title = @"Ask Where to Go First",
    .detail = @"Show a small floating address bar in the corner when you press ⌥⌘N instead of opening an empty Little Dia window first.",
    .symbol = @"magnifyingglass",
    .tint = @"systemMintColor",
    .requires = @"littleDia",
    .apply = DPApplyLittleDiaLauncher,
    .verify = DPVerifyLittleDiaLauncher,
};
