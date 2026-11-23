#import "StdPatch/Hide.h"

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
BOOL DPTesting = YES;

void DPAddLaunchFlag(NSString *flag) {}
void DPDropLaunchFlag(NSString *flag) {}
void DPHandOffAndQuit(NSArray<NSString *> *args) {}
void DPInstallAIRows(void) {}
void DPApplyAIRows(void) {}
void DPDismissConnectAppPrompts(void) {}
BOOL DPIsSingleAppUpsellBar(NSView *view) { return NO; }
BOOL DPShortcutRecording(void) { return NO; }
BOOL DPSavedOn(DPPatch *patch) { return NO; }
void DPOnLaunch(void (^block)(void)) {}

#import "Patches/HideChatButton/HideChatButton.m"
#import "Patches/TurnOffAI/TurnOffAI.m"
#import "StdPatch/Hide.m"
#import "StdPatch/HideHosts.m"

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC13NavigationBar26NavigationBarCapsuleButton : NSButton
@end
@implementation _TtC13NavigationBar26NavigationBarCapsuleButton
@end

@interface _TtC5TabUI21TabPopoverActionsView : NSView
@end
@implementation _TtC5TabUI21TabPopoverActionsView
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

static _TtC13NavigationBar26NavigationBarCapsuleButton *makeAskCapsule(BOOL withAction, BOOL withChatFill, NSString *toolTip, NSString *title) {
    _TtC13NavigationBar26NavigationBarCapsuleButton *button = [[_TtC13NavigationBar26NavigationBarCapsuleButton alloc] initWithFrame:NSMakeRect(0, 0, 72, 28)];
    if (withAction) button.action = @selector(didClickAskButton:);
    button.toolTip = toolTip;
    if (withChatFill) {
        NSView *holder = [[NSView alloc] initWithFrame:NSZeroRect];
        holder.hidden = YES;
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.accessibilityLabel = @"chat fill";
        [holder addSubview:icon];
        [button addSubview:holder];
    }
    if (title) {
        NSTextField *label = [NSTextField labelWithString:title];
        [button addSubview:label];
    }
    return button;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        DPPatch *patches[] = { &DPHideChatButton, &DPTurnOffAI };
        DPPatches = patches;
        DPPatchCount = 2;

        DPHideChatButton.on = NO;
        DPTurnOffAI.on = NO;
        DPInstallHides();

        DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 600)
                                                               styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];
        _TtC13NavigationBar17NavigationBarView *toolbar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 560, 1000, 40)];

        // 1.58.0 toolbar button with accessibilityLabel = "Chat with this tab"
        NSButton *legacyChat = [[NSButton alloc] initWithFrame:NSMakeRect(900, 6, 70, 28)];
        legacyChat.accessibilityLabel = @"Chat with this tab";

        // 1.58.1+ "Ask" capsule button: no accessibilityLabel, no toolTip, hidden "chat fill" image + "Ask" text
        _TtC13NavigationBar26NavigationBarCapsuleButton *askByIconOnly = makeAskCapsule(NO, YES, nil, @"Ask");
        // 1.58.1+/1.59.0 "Ask" capsule button matched by didClickAskButton: action (e.g. Split View tooltip)
        _TtC13NavigationBar26NavigationBarCapsuleButton *askByAction = makeAskCapsule(YES, NO, @"Chat with these tabs", @"Chat with Tabs");
        _TtC13NavigationBar26NavigationBarCapsuleButton *askByTooltip = makeAskCapsule(NO, NO, @"Chat with this tab", @"Chat about…");
        _TtC13NavigationBar26NavigationBarCapsuleButton *diaHiddenAsk = makeAskCapsule(YES, YES, nil, @"Ask");
        diaHiddenAsk.hidden = YES;

        // Other NavigationBarCapsuleButtons in Dia 1.58.0/1.59.0 that must NEVER be hidden
        _TtC13NavigationBar26NavigationBarCapsuleButton *shareCapsule = makeAskCapsule(NO, NO, @"Share", @"Share");
        shareCapsule.action = @selector(didClickShareButton:);
        _TtC13NavigationBar26NavigationBarCapsuleButton *exportCapsule = makeAskCapsule(NO, NO, @"Export logs", @"Export Logs");
        exportCapsule.action = @selector(didClickExportLogsButton:);
        _TtC13NavigationBar26NavigationBarCapsuleButton *popupCapsule = makeAskCapsule(NO, NO, nil, @"Open pop-up window");
        popupCapsule.action = @selector(didClickPopUpButton:);

        for (NSView *v in @[ legacyChat, askByIconOnly, askByAction, askByTooltip, diaHiddenAsk, shareCapsule, exportCapsule, popupCapsule ])
            [toolbar addSubview:v];
        [window.contentView addSubview:toolbar];

        _TtC5TabUI21TabPopoverActionsView *popoverActions = [[_TtC5TabUI21TabPopoverActionsView alloc] initWithFrame:NSMakeRect(0, 0, 120, 30)];
        NSButton *cardChat = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
        cardChat.accessibilityLabel = @"Chat with this tab";
        [popoverActions addSubview:cardChat];

        check("DPIsChatButton matches legacy label button", DPIsChatButton(legacyChat));
        check("DPIsChatButton matches Ask capsule by chat fill subview", DPIsChatButton(askByIconOnly));
        check("DPIsChatButton matches Ask capsule by didClickAskButton: action", DPIsChatButton(askByAction));
        check("DPIsChatButton matches Ask capsule by tooltip", DPIsChatButton(askByTooltip));
        check("DPIsChatButton ignores Share capsule", !DPIsChatButton(shareCapsule));
        check("DPIsChatButton ignores Export Logs capsule", !DPIsChatButton(exportCapsule));
        check("DPIsChatButton ignores Pop-up blocker capsule", !DPIsChatButton(popupCapsule));
        check("DPIsAIView matches Ask capsule", DPIsAIView(askByIconOnly) && DPIsAIView(askByAction) && DPIsAIView(askByTooltip));
        check("DPIsAIView matches TabPopoverActionsView chat button", DPIsAIView(cardChat));
        check("DPIsAIView ignores non-chat capsules", !DPIsAIView(shareCapsule) && !DPIsAIView(exportCapsule) && !DPIsAIView(popupCapsule));

        [toolbar layout];
        check("off at launch keeps visible chat buttons visible",
              !legacyChat.hidden && !askByIconOnly.hidden && !askByAction.hidden && !askByTooltip.hidden);
        check("off at launch keeps Dia-hidden ask button hidden", diaHiddenAsk.hidden);
        check("off at launch keeps DPSuppressed empty", DPSuppressed.count == 0);
        check("off at launch verifies clean", !DPVerifyHides(&DPHideChatButton) && !DPVerifyHides(&DPTurnOffAI));

        DPHideChatButton.on = YES;
        DPApplyHides(&DPHideChatButton);
        check("Hide Chat Button hides legacy + all Ask capsule variants",
              legacyChat.hidden && askByIconOnly.hidden && askByAction.hidden && askByTooltip.hidden && diaHiddenAsk.hidden);
        check("Hide Chat Button never hides Share/Export/PopUp capsules",
              !shareCapsule.hidden && !exportCapsule.hidden && !popupCapsule.hidden);
        check("Hide Chat Button does not track Dia-hidden button in DPSuppressed", ![DPSuppressed containsObject:diaHiddenAsk]);
        check("Hide Chat Button blocks Dia re-showing Ask capsule while on", ({
            askByIconOnly.hidden = NO;
            askByAction.hidden = NO;
            askByIconOnly.hidden && askByAction.hidden;
        }));
        check("Share capsule setHidden: passes through while Hide Chat Button is on", ({
            shareCapsule.hidden = YES;
            BOOL hid = shareCapsule.hidden;
            shareCapsule.hidden = NO;
            hid && !shareCapsule.hidden;
        }));
        check("Hide Chat Button verifies clean while on", !DPVerifyHides(&DPHideChatButton));

        DPTurnOffAI.on = YES;
        DPApplyHides(&DPTurnOffAI);
        DPHideChatButton.on = NO;
        DPApplyHides(&DPHideChatButton);
        check("Turn Off AI keeps chat/Ask buttons hidden after Hide Chat Button turns off",
              legacyChat.hidden && askByIconOnly.hidden && askByAction.hidden && askByTooltip.hidden);
        check("Turn Off AI verifies clean while on", !DPVerifyHides(&DPTurnOffAI));

        DPTurnOffAI.on = NO;
        DPApplyHides(&DPTurnOffAI);
        check("turning both off restores all visible chat/Ask buttons",
              !legacyChat.hidden && !askByIconOnly.hidden && !askByAction.hidden && !askByTooltip.hidden);
        check("turning both off leaves Dia-hidden Ask button hidden", diaHiddenAsk.hidden);
        check("turning both off clears DPSuppressed", DPSuppressed.count == 0);
        check("turning both off verifies clean", !DPVerifyHides(&DPHideChatButton) && !DPVerifyHides(&DPTurnOffAI));

        DPTurnOffAI.on = YES;
        DPApplyHides(&DPTurnOffAI);
        DPEnforceHides(popoverActions);
        check("Turn Off AI alone hides legacy + Ask capsules + card chat button",
              legacyChat.hidden && askByIconOnly.hidden && askByAction.hidden && askByTooltip.hidden && cardChat.hidden);
        check("Turn Off AI alone leaves Share/Export/PopUp visible",
              !shareCapsule.hidden && !exportCapsule.hidden && !popupCapsule.hidden);
        DPTurnOffAI.on = NO;
        DPApplyHides(&DPTurnOffAI);
        check("Turn Off AI off restores card chat button and Ask capsules",
              !cardChat.hidden && !askByIconOnly.hidden && !askByAction.hidden && !askByTooltip.hidden && diaHiddenAsk.hidden && DPSuppressed.count == 0);
    }
    if (failures) return 1;
    puts("PASS: hide-chat-button");
    return 0;
}
