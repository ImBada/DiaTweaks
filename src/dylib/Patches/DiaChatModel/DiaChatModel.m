#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import "Patches/AgentTransport/AgentRelay.h"
#import "Patches/AgentTransport/AgentSocket.h"

NSData *DPChatAgentRequest(NSData *line, NSString *model);
NSArray<NSString *> *DPInstalledChatModels(void);
NSString *DPSelectedDiaChatModel(NSString *choice, NSArray<NSString *> *models, BOOL fallback);

extern DPPatch DPDiaChatModel, DPDiaChatModelFallback, DPTurnOffAI;
void DPInstallDiaModelOverview(void);
void DPRefreshDiaModelPicker(void);
NSString *DPVerifyDiaModelOverview(DPPatch *patch);

static NSString *const DPDefaultDiaModel = @"dia-default";

static BOOL gOfferedRelaunch, gAppliedTurnOffAI;

BOOL DPChatModelNeedsRelaunch(DPPatch *patch) {
    return patch->on && DPSavedOn(patch) && !DPTurnOffAI.on && DPAgentTransportInstalled() &&
        !DPAgentRelayRunning() && DPAgentServerRunning();
}

BOOL DPChatModelTakeRelaunchOffer(DPPatch *patch) {
    if (!patch->on) gOfferedRelaunch = NO;
    if (gOfferedRelaunch || !DPChatModelNeedsRelaunch(patch)) return NO;
    return gOfferedRelaunch = YES;
}

static void DPOfferChatModelRelaunch(DPPatch *patch) {
    if (DPTesting || !DPChatModelTakeRelaunchOffer(patch)) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Relaunch Dia to choose a chat model";
    alert.informativeText = @"Dia's chat helper is already running without DiaTweaks.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

void DPApplyDiaChatModel(DPPatch *patch) {
    gAppliedTurnOffAI = DPTurnOffAI.on;
    BOOL active = patch->on && !gAppliedTurnOffAI;
    NSString *model = active ? DPSelectedDiaChatModel(DPChoice(patch), DPInstalledChatModels(), DPDiaChatModelFallback.on) : nil;
    DPAgentFilter filter = nil;
    if (active) filter = ^NSData *(NSData *line, DPAgentReply reply) {
        return DPTurnOffAI.on ? line : DPChatAgentRequest(line, model);
    };
    DPSetAgentFilters(patch->key, filter, nil);
    DPRefreshDiaModelPicker();
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
    DPOfferChatModelRelaunch(patch);
}

static void DPInstallDiaChatModel(void) {
    DPInstallDiaModelOverview();
    DPApplyDiaChatModel(&DPDiaChatModel);
    DPOnLaunch(^{ DPApplyDiaChatModel(&DPDiaChatModel); });
    [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (DPDiaChatModel.on && DPTurnOffAI.on != gAppliedTurnOffAI) DPApplyDiaChatModel(&DPDiaChatModel);
    }];
}

NSMenu *DPDiaChatModels(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Model"];
    [menu addItemWithTitle:@"Dia Default" action:nil keyEquivalent:@""].representedObject = DPDefaultDiaModel;
    NSArray *models = DPInstalledChatModels();
    for (NSString *model in models)
        [menu addItemWithTitle:model action:nil keyEquivalent:@""].representedObject = model;
    NSString *saved = DPChoice(&DPDiaChatModel);
    if (!DPDiaChatModelFallback.on && saved.length && ![saved isEqual:DPDefaultDiaModel] && ![models containsObject:saved])
        [menu addItemWithTitle:saved action:nil keyEquivalent:@""].representedObject = saved;
    return menu;
}

static NSString *DPVerifyDiaChatModel(DPPatch *patch) {
    BOOL active = patch->on && !DPTurnOffAI.on;
    if (active && !DPAgentTransportInstalled()) return @"Dia's agent launch doesn't reach the chat model filter";
    if (!active && DPAgentFiltersActive()) return @"a chat model filter is registered while the tweak is off";
    return DPVerifyDiaModelOverview(patch);
}

DP_PATCH(DPDiaChatModel) {
    .key = @"diaChatModel",
    .order = 260,
    .title = @"Chat Model",
    .detail = @"Choose which model Dia’s chat uses, from the models Dia already lists. If Dia’s chat helper was already running when you turn this on, DiaTweaks offers to relaunch Dia.",
    .hint = @"Your account decides which models work, and Dia’s own upgrade prompts still apply.",
    .symbol = @"sparkles",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .disabledBy = @"turnOffAI",
    .classes = DPClasses(DPDiaAssistantPanel),
    .choice = @"diaChatModelChoice",
    .defaultChoice = @"dia-default",
    .choices = DPDiaChatModels,
    .install = DPInstallDiaChatModel,
    .apply = DPApplyDiaChatModel,
    .verify = DPVerifyDiaChatModel,
};
