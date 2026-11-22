#import "StdPatch/StdPatch.h"

extern DPPatch DPDiaChatModel;
void DPApplyDiaChatModel(DPPatch *patch);

static void DPApplyModelFallback(DPPatch *patch) {
    DPApplyDiaChatModel(&DPDiaChatModel);
}

DP_PATCH(DPDiaChatModelFallback) {
    .key = @"diaChatModelFallback",
    .defaultOn = YES,
    .order = 261,
    .title = @"Fall Back to Dia Default",
    .detail = @"Use Dia Default when the saved model is no longer listed.",
    .symbol = @"arrow.uturn.backward",
    .tint = @"systemPurpleColor",
    .requires = @"diaChatModel",
    .apply = DPApplyModelFallback,
};
