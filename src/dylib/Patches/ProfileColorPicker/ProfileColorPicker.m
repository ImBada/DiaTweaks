#import "ProfileColorPicker.h"

static void DPInstallProfileColorPicker(void) {
    DPInstallProfileColorTint();
    DPInstallProfileColorUI();
}

static void DPApplyProfileColorPicker(DPPatch *patch) {
    DPApplyProfileColorUI(patch->on);
    DPRefreshProfileColors();
}

static NSString *DPVerifyProfileColorPicker(DPPatch *patch) {
    return DPVerifyProfileColorUI(patch) ?: DPVerifyProfileColorTint(patch);
}

DP_PATCH(DPProfileColorPicker) {
    .key = @"profileColorPicker",
    .order = 84,
    .title = @"Profile Color Picker",
    .detail = @"Pick any custom color or enter a hex value in Settings › Profiles to tint each profile’s window, sidebar, and tab bar.",
    .symbol = @"paintpalette.fill",
    .tint = @"systemRedColor",
    .section = @"Profiles",
    .classes = DPClasses(DPDiaProfilePane, DPDiaThemePicker, DPDiaWindowTint, DPDiaGradientView),
    .install = DPInstallProfileColorPicker,
    .apply = DPApplyProfileColorPicker,
    .verify = DPVerifyProfileColorPicker,
};
