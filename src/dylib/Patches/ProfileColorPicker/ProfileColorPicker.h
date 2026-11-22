#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileColorPicker;

NSColor *DPColorFromHex(NSString *hex, NSString **canonical);
NSColor *DPColorFromSixDigitHex(NSString *hex, NSString **canonical);
NSString *DPHexFromColor(NSColor *color);
NSArray *DPProfileGradientColors(NSColor *base, BOOL dark, double intensity);

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

@interface DPProfileColorWell : NSColorWell
@end

@interface DPProfileHexField : NSTextField <NSTextFieldDelegate>
@end

@interface DPProfileColorRow : NSView
@property (copy) NSString *spaceID;
@property (strong) DPProfileColorWell *well;
@property (strong) DPProfileHexField *hexField;
@property (strong) NSButton *clearButton;
@property (nonatomic) BOOL suppressCommit;
- (instancetype)initWithSpaceID:(NSString *)spaceID font:(NSFont *)font textColor:(NSColor *)textColor;
- (void)syncFromDefaults:(BOOL)forceField;
- (void)switchToSpaceID:(NSString *)spaceID;
- (void)prepareForRemoval;
- (void)applyHex:(NSString *)canonical fromField:(BOOL)fromField;
- (void)clearColor;
@end
