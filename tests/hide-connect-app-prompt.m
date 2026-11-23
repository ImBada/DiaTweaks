#import "StdPatch/Hide.h"

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
BOOL DPTesting = YES;

void DPAddLaunchFlag(NSString *flag) {}
void DPDropLaunchFlag(NSString *flag) {}
void DPHandOffAndQuit(NSArray<NSString *> *args) {}
void DPInstallAIRows(void) {}
void DPApplyAIRows(void) {}
BOOL DPShortcutRecording(void) { return NO; }
BOOL DPSavedOn(DPPatch *patch) { return !patch->on; }
void DPOnLaunch(void (^block)(void)) {}

#import "Patches/HideConnectAppPrompts/HideConnectAppPrompts.m"
#import "Patches/TurnOffAI/TurnOffAI.m"
#import "StdPatch/Hide.m"
#import "StdPatch/HideHosts.m"
#import "runloop.h"

@interface _TtC6Dialog12DialogButton : NSButton
@end
@implementation _TtC6Dialog12DialogButton
@end

@interface _TtC9AppUpsell26RebrandedUpsellContentView : NSView
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *autoConnectCheckbox;
@end
@implementation _TtC9AppUpsell26RebrandedUpsellContentView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 360, 160)])) return nil;
    _titleLabel = [NSTextField labelWithString:title];
    _messageLabel = [NSTextField labelWithString:message];
    _autoConnectCheckbox = [NSButton checkboxWithTitle:@"Automatically connect my logged-in apps" target:nil action:nil];
    _autoConnectCheckbox.state = NSControlStateValueOn;
    [self addSubview:_titleLabel];
    [self addSubview:_messageLabel];
    [self addSubview:_autoConnectCheckbox];
    return self;
}
@end

typedef NS_ENUM(NSInteger, DPTestOutcome) {
    DPTestOutcomeNone = 0,
    DPTestOutcomeAccepted = 1,
    DPTestOutcomeDeclined = 2,
};

@interface _TtC6Dialog15DialogPanelView : NSView
@property (nonatomic) NSInteger acceptCount;
@property (nonatomic) NSInteger declineCount;
@property (nonatomic) NSInteger totalClicks;
@property (nonatomic) NSInteger continuationResumes;
@property (nonatomic) DPTestOutcome outcome;
@property (nonatomic) BOOL autoConnectPersisted;
@property (nonatomic, strong) _TtC9AppUpsell26RebrandedUpsellContentView *upsellContent;
@property (nonatomic, copy) void (^onDismiss)(void);
@end

@implementation _TtC6Dialog15DialogPanelView
- (void)handleButton:(id)sender {
    NSString *title = [sender isKindOfClass:NSButton.class] ? ((NSButton *)sender).title : nil;
    self.totalClicks++;
    if (DPIsDeclineTitle(title)) {
        self.declineCount++;
        if (self.outcome == DPTestOutcomeNone) {
            self.outcome = DPTestOutcomeDeclined;
            self.continuationResumes++;
        }
    } else {
        self.acceptCount++;
        if (self.upsellContent && self.upsellContent.autoConnectCheckbox.state == NSControlStateValueOn)
            self.autoConnectPersisted = YES;
        if (self.outcome == DPTestOutcomeNone) {
            self.outcome = DPTestOutcomeAccepted;
            self.continuationResumes++;
        }
    }
    if (self.onDismiss) self.onDismiss();
}
@end

@interface _TtC6Dialog25DialogPanelViewController : NSViewController
@property (nonatomic, strong) _TtC6Dialog15DialogPanelView *dialogView;
@property (nonatomic) BOOL dismissed;
@end

@implementation _TtC6Dialog25DialogPanelViewController
- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.dialogView) [self.view addSubview:self.dialogView];
}
- (void)dismissOverlay {
    self.dismissed = YES;
    [self.view removeFromSuperview];
}
@end

@interface _TtC6Dialog27DialogPanelWindowController : NSWindowController
@property (nonatomic) BOOL closed;
@end
@implementation _TtC6Dialog27DialogPanelWindowController
@end

@interface _TtC13AppsUpsellBar17AppsUpsellBarView : NSView
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSButton *connectButton;
@property (nonatomic, strong) NSButton *dismissButton;
@end
@implementation _TtC13AppsUpsellBar17AppsUpsellBarView
@end

static NSMutableArray<NSWindow *> *gTestWindows;
static char gSheetsKey;
static char gSheetHandlersKey;
static char gShownKey;
static char gClosedKey;
static NSInteger gBeginSheetCalls;
static NSInteger gMakeKeyCalls;
static NSInteger gOrderFrontCalls;

static NSArray<NSWindow *> *DPStubApp_windows(NSApplication *self, SEL _cmd) {
    return gTestWindows.copy ?: @[];
}

static NSArray<NSWindow *> *DPStubWindow_sheets(NSWindow *self, SEL _cmd) {
    NSMutableArray<NSWindow *> *sheets = DPGet(self, &gSheetsKey);
    return sheets.copy ?: @[];
}

static void DPStubWindow_beginSheet(NSWindow *self, SEL _cmd, NSWindow *sheet, void (^handler)(NSModalResponse)) {
    gBeginSheetCalls++;
    NSMutableArray<NSWindow *> *sheets = DPGet(self, &gSheetsKey);
    if (!sheets) {
        sheets = [NSMutableArray array];
        DPSet(self, &gSheetsKey, sheets);
    }
    [sheets addObject:sheet];
    NSMapTable<NSWindow *, id> *handlers = DPGet(self, &gSheetHandlersKey);
    if (!handlers) {
        handlers = [NSMapTable weakToStrongObjectsMapTable];
        DPSet(self, &gSheetHandlersKey, handlers);
    }
    if (handler) [handlers setObject:[handler copy] forKey:sheet];
}

static void DPStubWindow_endSheet(NSWindow *self, SEL _cmd, NSWindow *sheet) {
    NSMutableArray<NSWindow *> *sheets = DPGet(self, &gSheetsKey);
    [sheets removeObject:sheet];
    NSMapTable<NSWindow *, id> *handlers = DPGet(self, &gSheetHandlersKey);
    void (^handler)(NSModalResponse) = [handlers objectForKey:sheet];
    [handlers removeObjectForKey:sheet];
    if (handler) handler(NSModalResponseCancel);
}

static void DPStubWindow_makeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) {
    gMakeKeyCalls++;
    DPSet(self, &gShownKey, @YES);
}

static void DPStubWindow_orderFront(NSWindow *self, SEL _cmd, id sender) {
    gOrderFrontCalls++;
    DPSet(self, &gShownKey, @YES);
}

static void DPStubWindow_close(NSWindow *self, SEL _cmd) {
    DPSet(self, &gClosedKey, @YES);
    if ([self.windowController isKindOfClass:_TtC6Dialog27DialogPanelWindowController.class])
        ((_TtC6Dialog27DialogPanelWindowController *)self.windowController).closed = YES;
    [gTestWindows removeObject:self];
}

static NSWindow *DPNewWindow(void) {
    return [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 260)
                                       styleMask:NSWindowStyleMaskBorderless
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
}

static _TtC6Dialog12DialogButton *DPMakeDialogButton(NSString *title, NSInteger tag, id target, SEL action) {
    _TtC6Dialog12DialogButton *button = [[_TtC6Dialog12DialogButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 30)];
    button.title = title;
    button.tag = tag;
    button.target = target;
    button.action = action;
    return button;
}

static _TtC6Dialog15DialogPanelView *DPMakePanel(NSString *title, NSString *message, BOOL rebranded, NSString *primaryTitle, NSString *secondaryTitle) {
    _TtC6Dialog15DialogPanelView *panel = [[_TtC6Dialog15DialogPanelView alloc] initWithFrame:NSMakeRect(0, 0, 380, 220)];
    if (rebranded) {
        _TtC9AppUpsell26RebrandedUpsellContentView *content = [[_TtC9AppUpsell26RebrandedUpsellContentView alloc] initWithTitle:title message:message];
        panel.upsellContent = content;
        [panel addSubview:content];
    } else {
        NSTextField *titleLabel = [NSTextField labelWithString:title];
        NSTextField *msgLabel = [NSTextField labelWithString:message];
        [panel addSubview:titleLabel];
        [panel addSubview:msgLabel];
    }
    if (primaryTitle) [panel addSubview:DPMakeDialogButton(primaryTitle, 0, panel, @selector(handleButton:))];
    if (secondaryTitle) [panel addSubview:DPMakeDialogButton(secondaryTitle, 1, panel, @selector(handleButton:))];
    return panel;
}

static _TtC6Dialog27DialogPanelWindowController *DPMakePanelWC(_TtC6Dialog15DialogPanelView *panel) {
    NSWindow *w = DPNewWindow();
    [w.contentView addSubview:panel];
    _TtC6Dialog27DialogPanelWindowController *wc = [[_TtC6Dialog27DialogPanelWindowController alloc] initWithWindow:w];
    w.windowController = wc;
    return wc;
}

static _TtC13AppsUpsellBar17AppsUpsellBarView *DPMakeUpsellBar(NSString *subtitle) {
    _TtC13AppsUpsellBar17AppsUpsellBarView *bar = [[_TtC13AppsUpsellBar17AppsUpsellBarView alloc] initWithFrame:NSMakeRect(0, 0, 400, 44)];
    bar.subtitleLabel = [NSTextField labelWithString:subtitle];
    bar.connectButton = [NSButton buttonWithTitle:@"Connect GitHub" target:nil action:nil];
    bar.dismissButton = [NSButton buttonWithTitle:@"" target:nil action:nil];
    [bar addSubview:bar.subtitleLabel];
    [bar addSubview:bar.connectButton];
    [bar addSubview:bar.dismissButton];
    return bar;
}

static int failures;
static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gTestWindows = [NSMutableArray array];

        // Install headless AppKit stubs BEFORE patch hooks so DPCallOriginal chains into them.
        DPHookClass(NSApplication.class, @selector(windows), (IMP)DPStubApp_windows);
        DPHookClass(NSWindow.class, @selector(sheets), (IMP)DPStubWindow_sheets);
        DPHookClass(NSWindow.class, @selector(beginSheet:completionHandler:), (IMP)DPStubWindow_beginSheet);
        DPHookClass(NSWindow.class, @selector(endSheet:), (IMP)DPStubWindow_endSheet);
        DPHookClass(NSWindow.class, @selector(makeKeyAndOrderFront:), (IMP)DPStubWindow_makeKeyAndOrderFront);
        DPHookClass(NSWindow.class, @selector(orderFront:), (IMP)DPStubWindow_orderFront);
        DPHookClass(NSWindow.class, @selector(close), (IMP)DPStubWindow_close);

        DPPatch *patches[] = { &DPHideConnectAppPrompts, &DPTurnOffAI };
        DPPatches = patches;
        DPPatchCount = 2;

        DPHideConnectAppPrompts.on = NO;
        DPTurnOffAI.on = NO;
        DPInstallHides();
        DPHideConnectAppPrompts.install();

        NSWindow *browserWindow = DPNewWindow();
        [gTestWindows addObject:browserWindow];

        {
            _TtC6Dialog15DialogPanelView *panel = DPMakePanel(
                @"Connect SharePoint to Dia?",
                @"Dia will use sites and documents from SharePoint to give you better answers in Chat.",
                YES, @"OK", @"Don\u2019t connect SharePoint");
            _TtC6Dialog27DialogPanelWindowController *wc = DPMakePanelWC(panel);
            __block BOOL sheetDone = NO;
            __weak NSWindow *weakParent = browserWindow, *weakSheet = wc.window;
            panel.onDismiss = ^{ [weakParent endSheet:weakSheet]; };

            NSInteger before = gBeginSheetCalls;
            [browserWindow beginSheet:wc.window completionHandler:^(NSModalResponse r) { sheetDone = YES; }];
            DPDrainMainQueue(0.05);
            check("off: sheet presents normally without hiding or clicking",
                  gBeginSheetCalls == before + 1 && !panel.hidden && wc.window.alphaValue == 1.0 && !wc.window.ignoresMouseEvents
                  && panel.totalClicks == 0 && !sheetDone && browserWindow.sheets.count == 1);
            [browserWindow endSheet:wc.window];

            _TtC6Dialog15DialogPanelView *nonModal = DPMakePanel(
                @"Connect Slack to Dia?", @"Use Slack in Chat.", YES, @"OK", @"Don\u2019t connect Slack");
            _TtC6Dialog27DialogPanelWindowController *nwc = DPMakePanelWC(nonModal);
            NSInteger mkBefore = gMakeKeyCalls;
            [nwc.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("off: non-modal panel shows normally",
                  gMakeKeyCalls == mkBefore + 1 && !nonModal.hidden && nwc.window.alphaValue == 1.0 && nonModal.totalClicks == 0);
        }

        DPHideConnectAppPrompts.on = YES;
        {
            _TtC6Dialog15DialogPanelView *panel = DPMakePanel(
                @"Connect SharePoint to Dia?",
                @"Dia will use sites and documents from SharePoint to give you better answers in Chat.",
                YES, @"OK", @"Don\u2019t connect SharePoint");
            _TtC6Dialog27DialogPanelWindowController *wc = DPMakePanelWC(panel);
            __block BOOL sheetDone = NO;
            __weak NSWindow *weakParent = browserWindow, *weakSheet = wc.window;
            panel.onDismiss = ^{ [weakParent endSheet:weakSheet]; };

            [browserWindow beginSheet:wc.window completionHandler:^(NSModalResponse r) { sheetDone = YES; }];
            check("on (sheet): sheet hidden immediately before AppKit animation",
                  panel.hidden && wc.window.alphaValue == 0.0 && wc.window.ignoresMouseEvents
                  && wc.window.animationBehavior == NSWindowAnimationBehaviorNone);
            DPDrainMainQueue(0.05);
            check("on (sheet): Decline invoked once, Accept never invoked, autoConnect never persisted",
                  panel.declineCount == 1 && panel.acceptCount == 0 && panel.totalClicks == 1 && !panel.autoConnectPersisted);
            check("on (sheet): InChat continuation resumed once with declined and sheet completion fired",
                  panel.continuationResumes == 1 && panel.outcome == DPTestOutcomeDeclined && sheetDone && browserWindow.sheets.count == 0);
        }

        {
            _TtC6Dialog15DialogPanelView *panel1 = DPMakePanel(
                @"Connect Notion to Dia?", @"Legacy Notion prompt.", NO, @"Connect Notion", @"Not now");
            _TtC6Dialog27DialogPanelWindowController *wc1 = DPMakePanelWC(panel1);
            __weak NSWindow *weakW1 = wc1.window;
            panel1.onDismiss = ^{ [weakW1 close]; };
            NSInteger mkBefore = gMakeKeyCalls;
            [wc1.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("on (non-modal makeKeyAndOrderFront): never ordered front, declined once, closed cleanly",
                  gMakeKeyCalls == mkBefore && panel1.hidden && wc1.window.alphaValue == 0.0
                  && panel1.declineCount == 1 && panel1.acceptCount == 0 && wc1.closed);

            _TtC6Dialog15DialogPanelView *panel2 = DPMakePanel(
                @"Reconnect Slack to Dia?", @"Your connection to Slack expired. Reconnect to keep using it in Chat.",
                NO, @"Reconnect Slack", @"Not now");
            _TtC6Dialog27DialogPanelWindowController *wc2 = DPMakePanelWC(panel2);
            __weak NSWindow *weakW2 = wc2.window;
            panel2.onDismiss = ^{ [weakW2 close]; };
            NSInteger ofBefore = gOrderFrontCalls;
            [wc2.window orderFront:nil];
            DPDrainMainQueue(0.05);
            check("on (non-modal orderFront reconnect): never ordered front, declined once, never accepted",
                  gOrderFrontCalls == ofBefore && panel2.declineCount == 1 && panel2.acceptCount == 0 && wc2.closed);
        }

        {
            _TtC6Dialog15DialogPanelView *panel = DPMakePanel(
                @"Connect Google Drive to Dia?", @"Use Google Drive in Chat.", YES, @"OK", @"Don\u2019t connect Google Drive");
            _TtC6Dialog25DialogPanelViewController *vc = [_TtC6Dialog25DialogPanelViewController new];
            vc.dialogView = panel;
            __weak _TtC6Dialog25DialogPanelViewController *weakVC = vc;
            panel.onDismiss = ^{ [weakVC dismissOverlay]; };
            [vc view]; // triggers loadView + viewDidLoad
            check("on (overlay): viewDidLoad hides backdrop and panel before attaching", vc.view.hidden && panel.hidden);
            [browserWindow.contentView addSubview:vc.view];
            DPDrainMainQueue(0.05);
            check("on (overlay): Decline invoked once, Accept never invoked, overlay dismissed",
                  panel.declineCount == 1 && panel.acceptCount == 0 && vc.dismissed && !vc.view.superview);
        }

        {
            NSArray<NSArray<NSString *> *> *nonTargets = @[
                @[ @"SharePoint is now connected in Dia", @"Dia can now search SharePoint.", @"OK", @"Settings" ],
                @[ @"Choose your Salesforce environment", @"Pick Production or Sandbox.", @"Production", @"Cancel" ],
                @[ @"Pick the region where your data lives", @"Choose US or EU.", @"US", @"Cancel" ],
                @[ @"To get the most from Dia, we recommend connecting to Slack.", @"Disconnect anyway?", @"Keep connected", @"Disconnect" ],
                @[ @"Delete profile?", @"This cannot be undone.", @"Delete", @"Cancel" ],
            ];
            for (NSArray<NSString *> *spec in nonTargets) {
                _TtC6Dialog15DialogPanelView *panel = DPMakePanel(spec[0], spec[1], YES, spec[2], spec[3]);
                _TtC6Dialog27DialogPanelWindowController *wc = DPMakePanelWC(panel);
                NSInteger mkBefore = gMakeKeyCalls;
                [wc.window makeKeyAndOrderFront:nil];
                DPDrainMainQueue(0.05);
                check("non-target dialog stays visible and unclicked",
                      gMakeKeyCalls == mkBefore + 1 && !panel.hidden && wc.window.alphaValue == 1.0 && panel.totalClicks == 0);
            }

            // Malformed dialog matching title but lacking verified tag!=0 Decline button (only tag 0 OK or wrong action/tag).
            _TtC6Dialog15DialogPanelView *onlyOK = DPMakePanel(@"Connect Jira to Dia?", @"Prompt", YES, @"OK", nil);
            _TtC6Dialog27DialogPanelWindowController *okWC = DPMakePanelWC(onlyOK);
            NSInteger mkBefore = gMakeKeyCalls;
            [okWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("double-lock: prompt without verified Decline button is never hidden or clicked",
                  gMakeKeyCalls == mkBefore + 1 && !onlyOK.hidden && onlyOK.totalClicks == 0);

            _TtC6Dialog15DialogPanelView *tagZeroDecline = DPMakePanel(@"Connect Linear to Dia?", @"Prompt", YES, nil, nil);
            [tagZeroDecline addSubview:DPMakeDialogButton(@"Don\u2019t connect Linear", 0, tagZeroDecline, @selector(handleButton:))];
            _TtC6Dialog27DialogPanelWindowController *tzWC = DPMakePanelWC(tagZeroDecline);
            __weak NSWindow *weakTZ = tzWC.window;
            tagZeroDecline.onDismiss = ^{ [weakTZ close]; };
            mkBefore = gMakeKeyCalls;
            [tzWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("decline button tagged 0 (first in the array) is still dismissed via Decline",
                  gMakeKeyCalls == mkBefore && tagZeroDecline.hidden && tzWC.closed
                  && tagZeroDecline.declineCount == 1 && tagZeroDecline.acceptCount == 0);

            _TtC6Dialog15DialogPanelView *tagZeroAccept = DPMakePanel(@"Connect Linear to Dia?", @"Prompt", YES, nil, nil);
            [tagZeroAccept addSubview:DPMakeDialogButton(@"Connect Linear", 0, tagZeroAccept, @selector(handleButton:))];
            _TtC6Dialog27DialogPanelWindowController *taWC = DPMakePanelWC(tagZeroAccept);
            mkBefore = gMakeKeyCalls;
            [taWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("double-lock: a tag==0 button without a decline title is never hidden or clicked",
                  gMakeKeyCalls == mkBefore + 1 && !tagZeroAccept.hidden && tagZeroAccept.totalClicks == 0);
        }

        DPHideConnectAppPrompts.on = NO;
        DPTurnOffAI.on = NO;
        {
            _TtC6Dialog15DialogPanelView *sheetPanel = DPMakePanel(@"Connect Asana to Dia?", @"Asana", YES, @"OK", @"Don\u2019t connect Asana");
            _TtC6Dialog27DialogPanelWindowController *sheetWC = DPMakePanelWC(sheetPanel);
            __block BOOL sheetDone = NO;
            __weak NSWindow *weakParent = browserWindow, *weakSheet = sheetWC.window;
            sheetPanel.onDismiss = ^{ [weakParent endSheet:weakSheet]; };
            [browserWindow beginSheet:sheetWC.window completionHandler:^(NSModalResponse r) { sheetDone = YES; }];

            _TtC6Dialog15DialogPanelView *floatPanel = DPMakePanel(@"Connect GitHub to Dia?", @"GitHub", NO, @"Connect GitHub", @"Not now");
            _TtC6Dialog27DialogPanelWindowController *floatWC = DPMakePanelWC(floatPanel);
            __weak NSWindow *weakFloat = floatWC.window;
            floatPanel.onDismiss = ^{ [weakFloat close]; };
            [gTestWindows addObject:floatWC.window];
            [floatWC.window makeKeyAndOrderFront:nil];

            _TtC6Dialog15DialogPanelView *ovPanel = DPMakePanel(@"Connect Figma to Dia?", @"Figma", YES, @"OK", @"Don't connect Figma");
            _TtC6Dialog25DialogPanelViewController *ovVC = [_TtC6Dialog25DialogPanelViewController new];
            ovVC.dialogView = ovPanel;
            __weak _TtC6Dialog25DialogPanelViewController *weakOv = ovVC;
            ovPanel.onDismiss = ^{ [weakOv dismissOverlay]; };
            [browserWindow.contentView addSubview:ovVC.view];

            DPDrainMainQueue(0.05);
            check("pre-toggle: all 3 open prompts stay visible while off",
                  !sheetPanel.hidden && !floatPanel.hidden && !ovPanel.hidden
                  && sheetPanel.totalClicks == 0 && floatPanel.totalClicks == 0 && ovPanel.totalClicks == 0);

            DPHideConnectAppPrompts.on = YES;
            DPHideConnectAppPrompts.apply(&DPHideConnectAppPrompts);
            DPHideConnectAppPrompts.apply(&DPHideConnectAppPrompts);
            DPDrainMainQueue(0.05);
            check("toggle ON: dismisses already-visible sheet, non-modal panel, and overlay via Decline once each",
                  sheetDone && sheetPanel.declineCount == 1 && sheetPanel.acceptCount == 0
                  && floatWC.closed && floatPanel.declineCount == 1 && floatPanel.acceptCount == 0
                  && ovVC.dismissed && ovPanel.declineCount == 1 && ovPanel.acceptCount == 0);
        }

        DPHideConnectAppPrompts.on = NO;
        DPTurnOffAI.on = NO;
        {
            _TtC6Dialog15DialogPanelView *openPanel = DPMakePanel(@"Connect Confluence to Dia?", @"Confluence", YES, @"OK", @"Don\u2019t connect Confluence");
            _TtC6Dialog27DialogPanelWindowController *openWC = DPMakePanelWC(openPanel);
            __weak NSWindow *weakOpen = openWC.window;
            openPanel.onDismiss = ^{ [weakOpen close]; };
            [gTestWindows addObject:openWC.window];
            [openWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("Turn Off AI pre-toggle: open prompt visible", !openPanel.hidden && openPanel.totalClicks == 0);

            DPTurnOffAI.on = YES;
            DPTurnOffAI.apply(&DPTurnOffAI);
            DPDrainMainQueue(0.05);
            check("Turn Off AI ON dismisses open Connect App prompt via Decline",
                  openWC.closed && openPanel.declineCount == 1 && openPanel.acceptCount == 0);

            _TtC6Dialog15DialogPanelView *newPanel = DPMakePanel(@"Connect Box to Dia?", @"Box", YES, @"OK", @"Don\u2019t connect Box");
            _TtC6Dialog27DialogPanelWindowController *newWC = DPMakePanelWC(newPanel);
            __weak NSWindow *weakNew = newWC.window;
            newPanel.onDismiss = ^{ [weakNew close]; };
            NSInteger mkBefore = gMakeKeyCalls;
            [newWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("Turn Off AI ON suppresses new Connect App prompts even when Hide Connect App Prompt is off",
                  gMakeKeyCalls == mkBefore && newWC.closed && newPanel.declineCount == 1 && newPanel.acceptCount == 0);

            DPTurnOffAI.on = NO;
            DPTurnOffAI.apply(&DPTurnOffAI);
            _TtC6Dialog15DialogPanelView *afterOff = DPMakePanel(@"Connect SharePoint to Dia?", @"SharePoint", YES, @"OK", @"Don\u2019t connect SharePoint");
            _TtC6Dialog27DialogPanelWindowController *afterWC = DPMakePanelWC(afterOff);
            mkBefore = gMakeKeyCalls;
            [afterWC.window makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("both OFF again: future Connect App prompts present normally",
                  gMakeKeyCalls == mkBefore + 1 && !afterOff.hidden && afterOff.totalClicks == 0);
        }

        DPHideConnectAppPrompts.on = YES;
        DPTurnOffAI.on = NO;
        {
            _TtC6Dialog15DialogPanelView *panel = DPMakePanel(
                @"Connect SharePoint to Dia?", @"Use SharePoint in Chat.", YES, @"OK", @"Don\u2019t connect SharePoint");
            NSButton *acceptBtn = nil, *declineBtn = nil;
            for (NSView *sub in panel.subviews) {
                if ([sub isKindOfClass:_TtC6Dialog12DialogButton.class]) {
                    NSButton *b = (NSButton *)sub;
                    if (b.tag == 0) acceptBtn = b;
                    else if (b.tag == 1) declineBtn = b;
                }
            }
            _TtC6Dialog27DialogPanelWindowController *wc = DPMakePanelWC(panel);
            __block BOOL sheetDone = NO;
            __weak NSWindow *weakParent = browserWindow, *weakSheet = wc.window;
            panel.onDismiss = ^{ [weakParent endSheet:weakSheet]; };
            [browserWindow beginSheet:wc.window completionHandler:^(NSModalResponse r) { sheetDone = YES; }];
            // Simulate Return hotkey firing Accept before the queued async decline runs.
            [panel handleButton:acceptBtn];
            check("hotkey race: Accept button blocked while suppressed sheet awaits async decline",
                  panel.acceptCount == 0 && !panel.autoConnectPersisted && panel.continuationResumes == 0);
            DPDrainMainQueue(0.05);
            [panel handleButton:declineBtn];
            check("hotkey race + at-most-once: Decline fires exactly once, Accept never fires",
                  sheetDone && panel.declineCount == 1 && panel.acceptCount == 0 && panel.continuationResumes == 1 && !panel.autoConnectPersisted);

            _TtC6Dialog15DialogPanelView *togglePanel = DPMakePanel(
                @"Connect Linear to Dia?", @"Use Linear in Chat.", YES, @"OK", @"Don\u2019t connect Linear");
            _TtC6Dialog25DialogPanelViewController *toggleVC = [_TtC6Dialog25DialogPanelViewController new];
            toggleVC.dialogView = togglePanel;
            [toggleVC view]; // viewDidLoad runs while ON -> hides view & panel
            check("toggle-off race: viewDidLoad initially hides overlay while ON", toggleVC.view.hidden && togglePanel.hidden);
            DPHideConnectAppPrompts.on = NO;
            [browserWindow.contentView addSubview:toggleVC.view];
            DPDrainMainQueue(0.05);
            check("toggle-off race: turning OFF before attachment restores hidden overlay and does not decline",
                  !toggleVC.view.hidden && !togglePanel.hidden && togglePanel.totalClicks == 0 && !toggleVC.dismissed);
            [toggleVC.view removeFromSuperview];

            DPHideConnectAppPrompts.on = YES;
            _TtC6Dialog15DialogPanelView *sheetTogglePanel = DPMakePanel(
                @"Connect Notion to Dia?", @"Use Notion in Chat.", YES, @"OK", @"Don\u2019t connect Notion");
            _TtC6Dialog25DialogPanelViewController *sheetToggleVC = [_TtC6Dialog25DialogPanelViewController new];
            sheetToggleVC.dialogView = sheetTogglePanel;
            [sheetToggleVC view];
            NSWindow *sheetWin = DPNewWindow();
            _TtC6Dialog27DialogPanelWindowController *sheetToggleWC = [[_TtC6Dialog27DialogPanelWindowController alloc] initWithWindow:sheetWin];
            sheetWin.windowController = sheetToggleWC;
            [sheetWin.contentView addSubview:sheetToggleVC.view];
            DPHideConnectAppPrompts.on = NO;
            [sheetWin makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("toggle-off race (window): turning OFF before makeKeyAndOrderFront restores visibility",
                  !sheetToggleVC.view.hidden && !sheetTogglePanel.hidden && sheetTogglePanel.totalClicks == 0);

            DPHideConnectAppPrompts.on = YES;
            NSWindow *multiWin = DPNewWindow();
            _TtC6Dialog15DialogPanelView *decoy = DPMakePanel(@"Connect Fake to Dia?", @"No decline", YES, @"OK", nil);
            _TtC6Dialog15DialogPanelView *realPrompt = DPMakePanel(@"Connect Slack to Dia?", @"Real", YES, @"OK", @"Don\u2019t connect Slack");
            [multiWin.contentView addSubview:decoy];
            [multiWin.contentView addSubview:realPrompt];
            _TtC6Dialog27DialogPanelWindowController *multiWC = [[_TtC6Dialog27DialogPanelWindowController alloc] initWithWindow:multiWin];
            multiWin.windowController = multiWC;
            __weak NSWindow *weakMulti = multiWin;
            realPrompt.onDismiss = ^{ [weakMulti close]; };
            [multiWin makeKeyAndOrderFront:nil];
            DPDrainMainQueue(0.05);
            check("multi-panel container skips decoy without decline and suppresses valid Connect prompt",
                  decoy.totalClicks == 0 && realPrompt.declineCount == 1 && realPrompt.acceptCount == 0 && multiWC.closed);
        }

        DPHideConnectAppPrompts.on = YES;
        DPTurnOffAI.on = NO;
        {
            _TtC13AppsUpsellBar17AppsUpsellBarView *single = DPMakeUpsellBar(@"Bring the full context from GitHub into Dia");
            [browserWindow.contentView addSubview:single];
            [single layout];
            check("on: single-app upsell bar is hidden", single.hidden);

            _TtC13AppsUpsellBar17AppsUpsellBarView *allApps = DPMakeUpsellBar(@"Get better answers from your apps");
            [browserWindow.contentView addSubview:allApps];
            [allApps layout];
            check("on: all-apps upsell bar is left alone", !allApps.hidden);

            _TtC13AppsUpsellBar17AppsUpsellBarView *late = DPMakeUpsellBar(@"");
            [browserWindow.contentView addSubview:late];
            [late layout];
            check("on: unlabelled bar is not hidden yet", !late.hidden);
            late.subtitleLabel.stringValue = @"Bring the full context from Notion into Dia";
            [late layout];
            check("on: bar labelled after layout is hidden on the next pass", late.hidden);

            DPHideConnectAppPrompts.on = NO;
            DPHideConnectAppPrompts.apply(&DPHideConnectAppPrompts);
            check("off: single-app upsell bars are restored and the all-apps bar stays visible",
                  !single.hidden && !late.hidden && !allApps.hidden);
            [single removeFromSuperview];
            [late removeFromSuperview];
            [allApps removeFromSuperview];
        }

        DPHideConnectAppPrompts.on = NO;
        DPTurnOffAI.on = YES;
        {
            _TtC13AppsUpsellBar17AppsUpsellBarView *covered = DPMakeUpsellBar(@"Bring the full context from GitHub into Dia");
            [browserWindow.contentView addSubview:covered];
            [covered layout];
            check("turnOffAI alone: single-app upsell bar is hidden", covered.hidden);

            _TtC13AppsUpsellBar17AppsUpsellBarView *coveredLate = DPMakeUpsellBar(@"");
            [browserWindow.contentView addSubview:coveredLate];
            [coveredLate layout];
            check("turnOffAI alone: unlabelled bar is not hidden yet", !coveredLate.hidden);
            coveredLate.subtitleLabel.stringValue = @"Bring the full context from Notion into Dia";
            [coveredLate layout];
            check("turnOffAI alone: bar labelled after layout is hidden on the next pass", coveredLate.hidden);

            _TtC13AppsUpsellBar17AppsUpsellBarView *coveredAll = DPMakeUpsellBar(@"Get better answers from your apps");
            [browserWindow.contentView addSubview:coveredAll];
            [coveredAll layout];
            check("turnOffAI alone: all-apps upsell bar is left alone", !coveredAll.hidden);

            DPTurnOffAI.on = NO;
            DPTurnOffAI.apply(&DPTurnOffAI);
            check("turnOffAI off: single-app upsell bars are restored",
                  !covered.hidden && !coveredLate.hidden && !coveredAll.hidden);
            [covered removeFromSuperview];
            [coveredLate removeFromSuperview];
            [coveredAll removeFromSuperview];
        }

        check("patch metadata matches spec",
              [DPHideConnectAppPrompts.key isEqualToString:@"hideConnectAppPrompts"]
              && DPHideConnectAppPrompts.order == 220
              && [DPHideConnectAppPrompts.title isEqualToString:@"Hide Connect App Prompt"]
              && [DPHideConnectAppPrompts.section isEqualToString:@"AI"]
              && [DPHideConnectAppPrompts.tint isEqualToString:@"systemPurpleColor"]
              && [DPHideConnectAppPrompts.coveredBy isEqualToString:@"turnOffAI"]);
    }
    if (failures) return 1;
    puts("PASS: hide-connect-app-prompt");
    return 0;
}
