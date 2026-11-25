#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileColorPicker;

NSColor *DPColorFromHex(NSString *hex, NSString **canonical);
NSColor *DPColorFromSixDigitHex(NSString *hex, NSString **canonical);
NSString *DPHexFromColor(NSColor *color);
NSArray *DPProfileGradientColors(NSColor *base, BOOL dark, double intensity);
NSArray *DPProfileGradientColorsForHex(NSString *hex, BOOL dark, double intensity);

NSString *DPNormalizedSpaceID(id value);
NSString *DPSavedProfileHexForSpace(NSString *spaceID);
NSString *DPProfileHexForSpace(NSString *spaceID);
void DPSetProfileHexForSpace(NSString *spaceID, NSString *hex);

void DPInstallProfileColorTint(void);
void DPRefreshProfileColors(void);
void DPRefreshProfileColorForWindow(NSWindow *window);
NSString *DPVerifyProfileColorTint(DPPatch *patch);

void DPInstallProfileColorUI(void);
void DPApplyProfileColorUI(BOOL on);
void DPSyncProfileColorUI(NSString *spaceID);
NSString *DPVerifyProfileColorUI(DPPatch *patch);
NSString *DPProfilePaneSpaceID(NSViewController *pane);
NSString *DPAnchoredPanelSpaceID(NSWindow *window);
void DPRefreshPresetRings(NSView *picker);

static inline CGFloat DPUnit(CGFloat value) { return MIN(MAX(value, 0.0), 1.0); }

NSImage *DPProfileWheelImage(CGFloat side);

@interface DPProfileHexField : NSTextField <NSTextFieldDelegate>
@end

@interface DPProfileColorCircle : NSView
@property (copy) NSString *spaceID;
@property (nonatomic) BOOL popoverOpen;
@property (nonatomic, readonly) BOOL suppressesPresets;
@property (weak) NSView *picker;
- (instancetype)initWithSpaceID:(NSString *)spaceID dimension:(CGFloat)dimension;
- (void)syncFromDefaults;
- (void)switchToSpaceID:(NSString *)spaceID;
- (void)prepareForRemoval;
- (void)closePopover;
- (void)applyHex:(NSString *)canonical fromField:(BOOL)fromField;
- (void)clearColor;
@end
